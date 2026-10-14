import AppKit
import ApplicationServices
import Observation
import PadDisplayCore
import ServiceManagement
import UniformTypeIdentifiers

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
    private let shortcuts = ShortcutService()
    let updates = UpdateService()

    private(set) var profiles: [DeviceProfile]
    private(set) var controllers: [String] = []
    private(set) var permissionGranted = UUConnectionReader.authorized
    private(set) var connectionStatus = "正在检查连接…"
    private(set) var report = DisplayReport()
    var notice: String?
    var health: HealthReport?
    var checkingHealth = false
    var pendingImport: ProfileArchive?
    var needsSetup: Bool
    var restoreWindowPositions: Bool {
        didSet { preferences.set(restoreWindowPositions, forKey: "restoreWindows"); display.setWindowRestoration(restoreWindowPositions) }
    }
    var shortcutsEnabled: Bool {
        didSet { preferences.set(shortcutsEnabled, forKey: "shortcutsEnabled"); refreshShortcuts() }
    }
    var shortcutProblem: String?
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
    var favorites: [DeviceProfile] { Array(profiles.filter { $0.favorite && $0.enabled && $0.validationError == nil }.prefix(9)) }
    var currentProfile: DeviceProfile? {
        profiles.first { $0.id == report.active?.profileID } ?? profiles.first { controllers.contains($0.name) }
    }
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
        restoreWindowPositions = preferences.object(forKey: "restoreWindows") as? Bool ?? true
        shortcutsEnabled = preferences.bool(forKey: "shortcutsEnabled")
        needsSetup = preferences.object(forKey: "onboardingComplete") as? Bool == false ||
            (preferences.object(forKey: "onboardingComplete") == nil && preferences.data(forKey: "profiles") == nil)
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
        display.setWindowRestoration(restoreWindowPositions)
        display.recover()
        refreshShortcuts()
        updates.scheduleChecks()
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
        guard !profile.name.isEmpty, profile.name.count <= 128 else { notice = "请输入不超过 128 字的 UU远程设备名称。"; return false }
        guard !profiles.contains(where: { $0.id != profile.id && $0.name == profile.name }) else {
            notice = "此设备名称已经有配置，请编辑已有设备。"; return false
        }
        guard !profiles.contains(where: { $0.id != profile.id && $0.displaySerial == profile.displaySerial }) else {
            notice = "此配置的屏幕身份冲突，请新建设备配置。"; return false
        }
        if profile.enabled, let error = profile.validationError { notice = error; return false }
        guard profiles.count < 100 || profiles.contains(where: { $0.id == profile.id }) else {
            notice = "最多保存 100 台设备，请先移除不再使用的配置。"; return false
        }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        persist()
        notice = nil
        if manual?.profileID == profile.id { manual = profile.enabled ? DisplayRequest(profile) : nil }
        updateDisplay()
        return true
    }

    func makeDraft() -> DeviceProfile {
        let name = controllers.first(where: { n in !profiles.contains { $0.name == n } }) ?? ""
        return DeviceProfile.draft(for: name)
    }

    func remove(_ id: UUID) {
        if manual?.profileID == id { manual = nil }
        profiles.removeAll { $0.id == id }
        persist()
        updateDisplay()
    }

    func useManually(_ profile: DeviceProfile) {
        guard !companionRunning else { notice = "请先退出其他显示助手，避免同时调整显示器。"; return }
        guard let saved = profiles.first(where: { $0.id == profile.id }) else { notice = "此设备配置已不存在。"; return }
        guard saved.enabled, saved.validationError == nil else { return }
        manual = DisplayRequest(saved)
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

    func setDensity(_ density: DesktopDensity, for profile: DeviceProfile) { updateProfile(profile.id) { $0.density = density } }
    func setRegion(_ region: DisplayRegion, for profile: DeviceProfile) { updateProfile(profile.id) { $0.region = region } }
    func rotate(_ profile: DeviceProfile) { updateProfile(profile.id) { swap(&$0.spec.width, &$0.spec.height) } }
    func setFavorite(_ profile: DeviceProfile, _ favorite: Bool) { updateProfile(profile.id) { $0.favorite = favorite } }
    private func updateProfile(_ id: UUID, _ change: (inout DeviceProfile) -> Void) {
        guard var profile = profiles.first(where: { $0.id == id }) else { notice = "此设备配置已不存在。"; return }
        change(&profile)
        _ = save(profile)
    }
    func completeSetup() { needsSetup = false; preferences.set(true, forKey: "onboardingComplete") }

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
            if let error = profile.validationError { notice = error; display.request(nil) }
            else { display.request(DisplayRequest(profile)) }
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
        shortcuts.stop()
        updates.stopChecks()
        display.shutdown(completion)
    }

    private func received(_ reading: ConnectionReading) {
        controllers = tracker.update(reading.controllers, reportedCount: reading.controllerCount, now: Date())
        connectionStatus = reading.detail
        for name in controllers where !discovered.contains(name) {
            discovered.insert(name)
            if profiles.count < 100, !profiles.contains(where: { $0.name == name }), let preset = ScreenPreset.suggested(for: name) {
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
        refreshShortcuts()
    }

    func copyShortcutURL(for profile: DeviceProfile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("paddisplay://apply?device=\(profile.id.uuidString)", forType: .string)
    }

    func handleShortcut(_ url: URL) {
        guard url.scheme == "paddisplay", !report.busy else { return }
        switch url.host {
        case "restore": restore()
        case "automatic": resumeAutomatic()
        case "rotate": if let profile = currentProfile { rotate(profile) }
        case "apply":
            guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "device" })?.value,
                  let id = UUID(uuidString: value), let profile = profiles.first(where: { $0.id == id }) else {
                notice = "快捷指令中的设备配置已不存在，请重新复制链接。"; return
            }
            useManually(profile)
        default: break
        }
    }

    private func refreshShortcuts() {
        shortcuts.stop()
        guard started, shortcutsEnabled else { shortcutProblem = nil; return }
        shortcutProblem = shortcuts.register(count: favorites.count) { [weak self] index in
            guard let self, !self.report.busy else { return }
            if index == 0 { self.restore() }
            else if index == 10 { if let profile = self.currentProfile { self.rotate(profile) } }
            else if self.favorites.indices.contains(index - 1) { self.useManually(self.favorites[index - 1]) }
        }
    }

    func checkHealth() {
        guard !checkingHealth else { return }
        checkingHealth = true
        reader.sample { [weak self] reading in
            guard let self else { return }
            self.permissionGranted = UUConnectionReader.authorized
            self.health = Diagnostics.check(model: self, reading: reading)
            self.checkingHealth = false
        }
    }

    func exportHealth() {
        guard let health else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "PadDisplay-诊断.json"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do { try JSONEncoder.pretty.encode(health).write(to: url, options: .atomic) }
            catch { self.notice = "诊断导出失败：\(error.localizedDescription)" }
        }
    }

    func exportProfiles() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "PadDisplay-设备配置.json"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do { try JSONEncoder.pretty.encode(ProfileArchive(profiles: self.profiles)).write(to: url, options: .atomic) }
            catch { self.notice = "配置导出失败：\(error.localizedDescription)" }
        }
    }

    func importProfiles() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 1_048_576 else { throw NSError(domain: "PadDisplay", code: 1, userInfo: [NSLocalizedDescriptionKey: "配置文件不能超过 1 MB。"]) }
                self.pendingImport = try ProfileArchive.read(Data(contentsOf: url))
            } catch { self.notice = "未导入配置：\(error.localizedDescription)" }
        }
    }

    func acceptImport(replace: Bool) {
        guard let incoming = pendingImport else { return }
        do {
            let next = try incoming.merged(with: profiles, replace: replace)
            try FileManager.default.createDirectory(at: VirtualDisplayService.supportDirectory, withIntermediateDirectories: true)
            try JSONEncoder.pretty.encode(ProfileArchive(profiles: profiles)).write(to: backupURL, options: .atomic)
            profiles = next; pendingImport = nil; persist(); manual = nil; updateDisplay()
            notice = "已导入 \(incoming.profiles.count) 台设备；原配置已自动备份。"
        } catch { notice = "未改变现有配置：\(error.localizedDescription)" }
    }

    private var backupURL: URL { VirtualDisplayService.supportDirectory.appendingPathComponent("profiles-before-import.json") }
    var hasImportBackup: Bool { FileManager.default.fileExists(atPath: backupURL.path) }
    func recoverImportBackup() {
        do {
            let size = try backupURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw NSError(domain: "PadDisplay", code: 1, userInfo: [NSLocalizedDescriptionKey: "配置备份不能超过 1 MB。"]) }
            let archive = try ProfileArchive.read(Data(contentsOf: backupURL), allowingEmpty: true)
            profiles = archive.profiles; persist(); manual = nil; updateDisplay(); notice = "已恢复导入前的设备配置。"
        } catch { notice = "配置恢复失败：\(error.localizedDescription)" }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
