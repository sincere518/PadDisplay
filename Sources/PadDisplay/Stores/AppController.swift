import AppKit
import ApplicationServices
import Observation
import PadDisplayCore
import ServiceManagement

@MainActor @Observable
final class AppController {
    static let shared: AppController = {
        let args = CommandLine.arguments
        let scenario = args.firstIndex(of: "--ui-preview").map { index in
            index + 1 < args.count ? args[index + 1] : "ready"
        }
        return AppController(validationScenario: scenario)
    }()
    private let preferences: UserDefaults
    private let validationDomain: String?
    let validationScenario: String?
    private let reader = UUConnectionReader()
    let display = VirtualDisplayService()
    private var tracker = ConnectionTracker()
    private var timer: Timer?
    private var manual: DisplayRequest?
    private var suspended = false
    private var started = false
    private var discovered: Set<String> = []

    private(set) var profiles: [DeviceProfile]
    private(set) var controllers: [String] = []
    private(set) var permissionGranted = UUConnectionReader.authorized
    private(set) var connectionStatus = "正在检查连接…"
    private(set) var report = DisplayReport()
    var notice: String?
    var automatic: Bool {
        didSet {
            preferences.set(automatic, forKey: "automatic")
            suspended = false
            manual = nil
            updateDisplay()
        }
    }
    private(set) var loginEnabled = SMAppService.mainApp.status == .enabled

    var isValidation: Bool { validationScenario != nil }
    var sessionPaused: Bool { suspended }
    var manualMode: Bool { manual != nil }
    var connectionCount: Int { tracker.controllerCount }
    var sessionState: SessionState {
        if report.busy { return .working }
        if report.failed { return report.recoveryNeeded ? .recoveryFailed : .failed }
        if companionRunning { return .companion }
        if suspended { return .paused }
        if manual != nil, report.active != nil { return .manual }
        if !automatic { return .disabled }
        if connectionCount > 1 { return .multiple }
        if !permissionGranted { return .permission }
        if report.active != nil { return .ready }
        if controllers.contains(where: { name in !profiles.contains { $0.name == name } }) { return .unconfigured }
        return controllers.isEmpty ? .waiting : .inactive
    }

    var companionRunning: Bool {
        if isValidation { return validationScenario == "companion" }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: "com.corndog.uudisplay").isEmpty
    }

    init(preferences supplied: UserDefaults? = nil, validationScenario: String? = nil) {
        self.validationScenario = validationScenario
        let domain = validationScenario == nil || supplied != nil ? nil : "local.PadDisplay.UIValidation.\(UUID())"
        validationDomain = domain
        preferences = supplied ?? domain.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        automatic = preferences.object(forKey: "automatic") as? Bool ?? true
        if let data = preferences.data(forKey: "profiles"),
           let saved = try? JSONDecoder().decode([DeviceProfile].self, from: data) {
            profiles = saved
        } else {
            profiles = [DeviceProfile(name: "iPad Air (13 英寸, M2)", spec: ScreenPreset.all[0].spec)]
            if isValidation {
                profiles.append(DeviceProfile(name: "iPhone 17 Pro Max", spec: ScreenPreset.all.last!.spec))
            }
        }
        if isValidation { permissionGranted = true; loginEnabled = false }
    }

    func start() {
        guard !started else { return }
        started = true
        if let validationScenario { configureValidation(validationScenario); return }
        display.onChange = { [weak self] in self?.report = $0 }
        display.recover()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        permissionGranted = UUConnectionReader.authorized
        reader.sample { [weak self] reading in
            guard let self, self.started else { return }
            self.received(reading)
        }
    }

    @discardableResult func save(_ profile: DeviceProfile) -> Bool {
        var profile = profile
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.name.isEmpty else { notice = "请输入 UU远程中的设备名称。"; return false }
        guard !profiles.contains(where: { $0.id != profile.id && $0.name == profile.name }) else {
            notice = "此设备名称已经有配置，请编辑已有设备。"; return false
        }
        if profile.enabled, let error = profile.spec.validationError { notice = error; return false }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        persist()
        notice = nil
        updateDisplay()
        return true
    }

    func makeDraft() -> DeviceProfile {
        let name = controllers.first(where: { n in !profiles.contains { $0.name == n } }) ?? ""
        return DeviceProfile.draft(for: name)
    }

    func remove(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
        updateDisplay()
    }

    func useManually(_ profile: DeviceProfile) {
        guard !companionRunning else { notice = "请先退出 UU伴侣，避免两个软件同时调整显示器。"; return }
        guard save(profile), profile.enabled, profile.spec.validationError == nil else { return }
        manual = DisplayRequest(name: profile.name, spec: profile.spec)
        suspended = false
        requestDisplay(manual, retry: true)
    }

    func restore() {
        manual = nil
        suspended = true
        notice = nil
        requestDisplay(nil, retry: true)
    }

    func resumeAutomatic() { automatic = true }

    private func updateDisplay() {
        if companionRunning {
            connectionStatus = "请先退出 UU伴侣，避免同时调整显示器"
            requestDisplay(nil)
            return
        }
        if let manual { requestDisplay(manual); return }
        guard automatic, !suspended else { requestDisplay(nil); return }
        switch DeviceDecision.resolve(names: controllers, controllerCount: tracker.controllerCount, profiles: profiles) {
        case .use(let profile):
            if let error = profile.spec.validationError { notice = error; requestDisplay(nil) }
            else { requestDisplay(.init(name: profile.name, spec: profile.spec)) }
        case .configure(let name):
            connectionStatus = "新设备「\(name)」需要配置屏幕尺寸"
            requestDisplay(nil)
        case .simultaneous:
            connectionStatus = "多个设备同时连入，请保留一个连接后调整"
            requestDisplay(nil)
        case .idle:
            requestDisplay(nil)
        }
    }

    func openPermissions() {
        if isValidation { permissionGranted = true; return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    func openUU() {
        if isValidation { notice = "隔离验证实例不会打开其他应用。"; return }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.netease.uuremote") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { notice = "请先安装并打开 UU远程。" }
    }

    func setLogin(_ enabled: Bool) {
        if isValidation { loginEnabled = enabled; return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { notice = "请在系统设置的登录项中允许 PadDisplay。" }
        } catch { notice = "登录项设置失败：\(error.localizedDescription)" }
    }

    func shutdown(_ completion: @escaping () -> Void) {
        timer?.invalidate()
        started = false
        if isValidation {
            if let validationDomain { preferences.removePersistentDomain(forName: validationDomain) }
            completion()
            return
        }
        display.shutdown(completion)
    }

    private func received(_ reading: ConnectionReading) {
        controllers = tracker.update(reading.controllers, reportedCount: reading.controllerCount, now: Date())
        connectionStatus = reading.detail
        for name in controllers where !discovered.contains(name) {
            discovered.insert(name)
            if !profiles.contains(where: { $0.name == name }), let preset = ScreenPreset.suggested(for: name) {
                profiles.append(DeviceProfile(name: name, spec: preset.spec))
                persist()
            }
        }
        if tracker.controllerCount == 0, reading.controllers?.isEmpty == true {
            suspended = false
            discovered = []
        }
        updateDisplay()
    }

    private func requestDisplay(_ request: DisplayRequest?, retry: Bool = false) {
        guard isValidation else { display.request(request, retry: retry); return }
        report = .init(active: request, message: request == nil ? "已恢复原桌面" : "远程屏幕已就绪")
    }

    /// 隔离的原生 UI 验证：独立偏好域，不读取连接、不操作显示器或登录项。
    private func configureValidation(_ scenario: String) {
        let pad = profiles[0].name
        let names: [String] = switch scenario {
        case "idle", "permission": []
        case "phone": ["iPhone 17 Pro Max"]
        case "multiple": [pad, "iPhone 17 Pro Max"]
        case "unknown": ["我的手机"]
        default: [pad]
        }
        permissionGranted = scenario != "permission"
        received(.init(controllers: names, detail: names.isEmpty ? "等待远程设备连接" : "已识别连接设备", controllerCount: names.count))
        if scenario == "paused" { restore() }
        if scenario == "busy" { report = .init(busy: true, message: "正在准备远程屏幕…") }
        if scenario == "failed" { report = .init(message: "恢复记录已保留，请重试。", failed: true, recoveryNeeded: true) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { preferences.set(data, forKey: "profiles") }
    }
}
