import AppKit
import ApplicationServices
import Observation
import PadDisplayCore
import ServiceManagement

@MainActor @Observable
final class AppController {
    static let shared = AppController()
    private let preferences = UserDefaults.standard
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
        return !NSRunningApplication.runningApplications(withBundleIdentifier: "com.corndog.uudisplay").isEmpty
    }

    init() {
        automatic = preferences.object(forKey: "automatic") as? Bool ?? true
        if let data = preferences.data(forKey: "profiles"),
           let saved = try? JSONDecoder().decode([DeviceProfile].self, from: data) {
            profiles = saved
        } else {
            profiles = [DeviceProfile(name: "iPad Air (13 英寸, M2)", spec: ScreenPreset.all[0].spec)]
        }
    }

    func start() {
        guard !started else { return }
        started = true
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
        guard !companionRunning else { notice = "请先退出其他显示助手，避免同时调整显示器。"; return }
        guard save(profile), profile.enabled, profile.spec.validationError == nil else { return }
        manual = DisplayRequest(name: profile.name, spec: profile.spec)
        suspended = false
        display.request(manual, retry: true)
    }

    func restore() {
        manual = nil
        suspended = true
        notice = nil
        display.request(nil, retry: true)
    }

    func resumeAutomatic() { automatic = true }

    private func updateDisplay() {
        if companionRunning {
            connectionStatus = "请先退出其他显示助手，避免同时调整显示器"
            display.request(nil)
            return
        }
        if let manual { display.request(manual); return }
        guard automatic, !suspended else { display.request(nil); return }
        switch DeviceDecision.resolve(names: controllers, controllerCount: tracker.controllerCount, profiles: profiles) {
        case .use(let profile):
            if let error = profile.spec.validationError { notice = error; display.request(nil) }
            else { display.request(.init(name: profile.name, spec: profile.spec)) }
        case .configure(let name):
            connectionStatus = "新设备「\(name)」需要配置屏幕尺寸"
            display.request(nil)
        case .simultaneous:
            connectionStatus = "多个设备同时连入，请保留一个连接后调整"
            display.request(nil)
        case .idle:
            display.request(nil)
        }
    }

    func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    func openUU() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.netease.uuremote") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { notice = "请先安装并打开 UU远程。" }
    }

    func setLogin(_ enabled: Bool) {
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

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { preferences.set(data, forKey: "profiles") }
    }
}
