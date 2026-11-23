import CoreGraphics
import DisplayBridge
import Foundation
import PadDisplayCore

struct DisplayRequest: Equatable {
    let profileID: UUID
    let name: String
    let spec: DisplaySpec
    let role: DisplayRole
    let serial: UInt32

    init(_ profile: DeviceProfile) {
        profileID = profile.id; name = profile.name; spec = profile.effectiveSpec
        role = profile.role; serial = profile.displaySerial
    }
}

struct DisplayReport {
    var active: DisplayRequest?
    var busy = false
    var message = "尚未创建远程屏幕"
    var failed = false
    var recoveryNeeded = false
    var warning: String?
}

/// 拓扑操作全部串行执行；新建与释放至少间隔 3 秒，主线程保持响应。
final class VirtualDisplayService {
    static let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PadDisplay", isDirectory: true)
    private let queue = DispatchQueue(label: "local.PadDisplay.displays")
    private let journal = VirtualDisplayService.supportDirectory.appendingPathComponent("display-session.json")
    private var desired: DisplayRequest?
    private var current: DisplayRequest?
    private var requestRevision = 0
    private var busy = false
    private var blocked = false
    private var needsRecovery = false
    private var shuttingDown = false
    private var quitCompletions: [() -> Void] = []
    // 以下数据只在 queue 上访问。
    private var handle: UnsafeMutableRawPointer?
    private var pendingRemoval: CGDirectDisplayID?
    private var born = Date.distantPast
    private var snapshot: DesktopSnapshot?
    private let windows = WindowLayoutService()
    private var restoreWindows = true
    private var configurationStalled = false
    var onChange: ((DisplayReport) -> Void)?

    func setWindowRestoration(_ enabled: Bool) { queue.async { self.restoreWindows = enabled } }

    static func displays() -> [CGDirectDisplayID] {
        (try? readOnlineDisplays()) ?? []
    }

    private static func readOnlineDisplays() throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var error = CGGetOnlineDisplayList(0, nil, &count)
        guard error == .success else { throw displayReadFailure(error) }
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        error = CGGetOnlineDisplayList(count, &ids, &count)
        guard error == .success else { throw displayReadFailure(error) }
        return Array(ids.prefix(Int(count)))
    }

    private static func displayReadFailure(_ error: CGError) -> NSError {
        NSError(domain: "PadDisplay", code: Int(error.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "无法读取显示器列表：\(error.rawValue)"])
    }

    func request(_ value: DisplayRequest?, retry: Bool = false) {
        guard !shuttingDown else { return }
        enqueue(value, retry: retry)
    }

    private func enqueue(_ value: DisplayRequest?, retry: Bool) {
        if retry || desired != value {
            requestRevision &+= 1
            blocked = false
        }
        desired = value
        reconcile()
    }

    func shutdown(_ completion: @escaping () -> Void) {
        if shuttingDown {
            if quitCompletions.isEmpty { completion() }
            else { quitCompletions.append(completion) }
            return
        }
        shuttingDown = true
        quitCompletions.append(completion)
        enqueue(nil, retry: true)
    }

    func recover() {
        guard !busy else { return }
        shuttingDown = false
        busy = true
        let previous = current
        let revision = requestRevision
        queue.async {
            var result = DisplayReport(message: "准备就绪")
            do {
                if self.hasDesktopChanges { result.warning = try self.remove(final: true) }
            } catch {
                result.active = self.handle == nil ? nil : previous
                result.message = error.localizedDescription
                result.failed = true
                result.recoveryNeeded = self.hasDesktopChanges
            }
            DispatchQueue.main.async {
                self.busy = false
                self.current = result.active
                self.blocked = result.failed && revision == self.requestRevision && self.desired == nil
                self.needsRecovery = result.recoveryNeeded
                self.onChange?(result)
                self.reconcile()
            }
        }
    }

    private func reconcile() {
        guard !busy else { return }
        if desired == current && !needsRecovery {
            if desired == nil, !quitCompletions.isEmpty {
                onChange?(.init(message: "已恢复原桌面"))
                finishShutdown()
            }
            return
        }
        guard !blocked else { return }
        let target = desired
        let previous = current
        let revision = requestRevision
        busy = true
        onChange?(.init(active: current, busy: true, message: target == nil ? "正在恢复原桌面…" : "正在准备远程屏幕…"))
        queue.async {
            var result = DisplayReport()
            var startingTarget = false
            do {
                if self.hasDesktopChanges { result.warning = try self.remove(final: target == nil) }
                if let target {
                    startingTarget = true
                    try self.create(target)
                    result.active = target
                    result.message = "远程屏幕已就绪：\(target.spec.label)"
                } else { result.message = "已恢复原桌面" }
            } catch {
                // 创建失败后收尾。若移除本身失败，保留恢复记录并等待重试。
                if startingTarget, !self.configurationStalled { _ = try? self.remove(final: true) }
                result.active = self.handle == nil ? nil : startingTarget ? target : previous
                result.message = error.localizedDescription
                result.failed = true
                result.recoveryNeeded = self.hasDesktopChanges
            }
            DispatchQueue.main.async {
                self.busy = false
                self.current = result.active
                let stillRequested = revision == self.requestRevision
                self.blocked = result.failed && stillRequested
                self.needsRecovery = result.recoveryNeeded
                self.onChange?(result)
                if target == nil, stillRequested, self.shuttingDown {
                    self.finishShutdown()
                } else {
                    self.reconcile()
                }
            }
        }
    }

    private var hasDesktopChanges: Bool {
        handle != nil || pendingRemoval != nil || snapshot != nil || FileManager.default.fileExists(atPath: journal.path)
    }

    private func finishShutdown() {
        let completions = quitCompletions
        quitCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func create(_ request: DisplayRequest) throws {
        if let problem = request.spec.validationError { throw failure(problem) }
        if snapshot == nil {
            let displays = try Self.readOnlineDisplays().map(SavedDisplay.init)
            guard displays.allSatisfy({ $0.mode != nil }) else { throw failure("无法记录原显示器模式，已停止创建远程屏幕。") }
            snapshot = DesktopSnapshot(displays: displays,
                                       windows: restoreWindows ? windows.capture() : [])
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: journal, options: .atomic)
        }
        if request.role == .extended {
            let online = try Self.readOnlineDisplays()
            guard snapshot?.displays.contains(where: {
                ($0.vendor != 0x756e6b6e || $0.model != 0x76697274) && $0.resolve(in: online) != nil
            }) == true else {
                throw failure("扩展模式需要一台当前在线的原显示器，请连接显示器或改用主显示器模式。")
            }
        }
        let spec = request.spec
        handle = PDDisplayCreate("PadDisplay · \(request.name)", UInt32(spec.width), UInt32(spec.height), request.serial)
        born = Date()
        guard let handle else { throw failure("系统没有成功创建虚拟屏幕。") }
        guard PDDisplayApply(handle, UInt32(spec.width), UInt32(spec.height), spec.hiDPI) else {
            throw failure("系统未接受此分辨率，请检查尺寸或关闭高清模式后重试。")
        }
        let id = PDDisplayID(handle)
        Thread.sleep(forTimeInterval: 3)
        let logicalWidth = spec.width / (spec.hiDPI ? 2 : 1), logicalHeight = spec.height / (spec.hiDPI ? 2 : 1)
        let modes = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
        guard try Self.readOnlineDisplays().contains(id), let mode = modes.first(where: {
            $0.pixelWidth == spec.width && $0.pixelHeight == spec.height && $0.width == logicalWidth && $0.height == logicalHeight
        }) else {
            throw failure("系统未提供目标分辨率与缩放模式，请调整尺寸或关闭 HiDPI 后重试。")
        }
        let online = try Self.readOnlineDisplays()
        if request.role == .main {
            let origin = CGDisplayBounds(id).origin
            try configure { config in
                let modeError = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
                if modeError != .success { return modeError }
                for display in online where display == id || CGDisplayMirrorsDisplay(display) == 0 {
                    let p = CGDisplayBounds(display).origin
                    let error = CGConfigureDisplayOrigin(config, display, Int32(p.x - origin.x), Int32(p.y - origin.y))
                    if error != .success { return error }
                }
                return .success
            }
        } else {
            let right = online.filter { $0 != id }.map { CGDisplayBounds($0).maxX }.max() ?? 0
            try configure { config in
                let error = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
                return error == .success ? CGConfigureDisplayOrigin(config, id, Int32(right), 0) : error
            }
        }
        Thread.sleep(forTimeInterval: 0.7)
        guard let applied = CGDisplayCopyDisplayMode(id), applied.pixelWidth == spec.width, applied.pixelHeight == spec.height,
              applied.width == logicalWidth, applied.height == logicalHeight else {
            throw failure("系统没有应用目标像素与逻辑桌面尺寸，请重试。")
        }
        if request.role == .main {
            guard CGMainDisplayID() == id else { throw failure("虚拟屏幕已创建，但未成为主显示器。") }
        } else {
            guard CGMainDisplayID() != id else { throw failure("扩展屏幕已创建，但系统没有保留原主显示器。") }
        }
    }

    private func remove(final: Bool) throws -> String? {
        if configurationStalled { throw failure("系统显示配置无响应，请注销或重启 Mac 后恢复。") }
        if snapshot == nil, FileManager.default.fileExists(atPath: journal.path) {
            snapshot = try DesktopSnapshot.read(Data(contentsOf: journal))
        }
        if let handle {
            Thread.sleep(forTimeInterval: max(0, 3 - Date().timeIntervalSince(born)))
            pendingRemoval = PDDisplayID(handle)
            PDDisplayRelease(handle)
            self.handle = nil
            Thread.sleep(forTimeInterval: 1.5)
        }
        if let id = pendingRemoval {
            guard try !Self.readOnlineDisplays().contains(id) else { throw failure("虚拟屏幕尚未移除，请稍后重试恢复。") }
            pendingRemoval = nil
        }
        return try restoreDesktop(final: final)
    }

    private func restoreDesktop(final: Bool) throws -> String? {
        guard let snapshot else { return nil }
        let online = try Self.readOnlineDisplays()
        var claimed = Set<CGDirectDisplayID>()
        let resolvedTargets = snapshot.displays.compactMap { record -> (SavedDisplay, CGDirectDisplayID)? in
            let identityCount = snapshot.displays.filter { $0.vendor == record.vendor && $0.model == record.model && $0.serial == record.serial }.count
            guard let id = record.resolve(in: online, allowFallback: identityCount == 1), claimed.insert(id).inserted else { return nil }
            return (record, id)
        }
        // 镜像从屏必须等原主屏上线；局部恢复不调整缺少原主屏的从屏。
        let resolved = Dictionary(uniqueKeysWithValues: resolvedTargets.map { ($0.0.id, $0.1) })
        let targets = resolvedTargets.filter { record, _ in
            guard let mirror = record.mirrorOf, mirror != 0 else { return true }
            return resolved[mirror] != nil
        }
        var modes: [CGDirectDisplayID: CGDisplayMode] = [:]
        for (record, id) in targets {
            if let saved = record.mode, !(CGDisplayCopyDisplayMode(id).map(saved.matches) ?? false) {
                let all = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
                guard let mode = all.first(where: { saved.matches($0) && $0.ioDisplayModeID == saved.modeID }) ??
                    all.first(where: saved.matches) else {
                    throw failure("原显示器的分辨率、缩放或刷新率暂不可用，请检查显示器后重试恢复。")
                }
                modes[id] = mode
            }
        }
        if !targets.isEmpty {
            let currentMirrors = Dictionary(uniqueKeysWithValues: targets.map { ($0.1, CGDisplayMirrorsDisplay($0.1)) })
            let expectedMirrors = Dictionary(uniqueKeysWithValues: targets.compactMap { record, id -> (CGDirectDisplayID, CGDirectDisplayID)? in
                guard let mirror = record.mirrorOf, let expected = mirror == 0 ? 0 : resolved[mirror] else { return nil }
                return (id, expected)
            })
            try configure { config in
                var detached = Set<CGDirectDisplayID>()
                for (_, id) in targets {
                    guard let current = currentMirrors[id], current != 0, let expected = expectedMirrors[id],
                          current != expected || modes[id] != nil || modes[current] != nil else { continue }
                    let error = CGConfigureDisplayMirrorOfDisplay(config, id, 0)
                    if error != .success { return error }
                    detached.insert(id)
                }
                for (record, id) in targets {
                    if let mode = modes[id] {
                        let error = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
                        if error != .success { return error }
                    }
                    // 设置从屏原点会解除镜像，布局只设置主屏和各独立显示器。
                    if (expectedMirrors[id] ?? currentMirrors[id]) == 0 {
                        let error = CGConfigureDisplayOrigin(config, id, record.x, record.y)
                        if error != .success { return error }
                    }
                }
                for (_, id) in targets {
                    guard let expected = expectedMirrors[id], expected != 0,
                          detached.contains(id) || currentMirrors[id] != expected else { continue }
                    let error = CGConfigureDisplayMirrorOfDisplay(config, id, expected)
                    if error != .success { return error }
                }
                return .success
            }
            Thread.sleep(forTimeInterval: 0.7)
        }
        if final, targets.count != snapshot.displays.count {
            throw failure("原显示器已断开或身份不明确。已恢复可用屏幕，恢复记录将保留，请重新连接后重试。")
        }
        for (record, id) in targets {
            if let mirror = record.mirrorOf, let expected = mirror == 0 ? 0 : resolved[mirror], CGDisplayMirrorsDisplay(id) != expected {
                throw failure("原显示器的镜像关系尚未恢复，请重试恢复。")
            }
            let origin = CGDisplayBounds(id).origin
            guard Int32(origin.x) == record.x, Int32(origin.y) == record.y,
                  record.mode == nil || CGDisplayCopyDisplayMode(id).map({ record.mode!.matches($0) }) == true else {
                throw failure("系统尚未完整恢复原显示器模式或布局，请重试恢复。")
            }
            if record.main == true, CGMainDisplayID() != id { throw failure("原主显示器尚未恢复，请重试恢复。") }
        }
        if final {
            let skipped = restoreWindows ? windows.restore(snapshot.windows) : 0
            if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }
            self.snapshot = nil
            return skipped == 0 ? nil : "显示器已恢复；\(skipped) 个窗口未允许恢复位置（如全屏或受保护窗口）。"
        }
        return targets.count == snapshot.displays.count ? nil : "原显示器暂不可用，原桌面恢复记录已保留；显示器上线后可重试恢复。"
    }

    private func configure(_ body: (CGDisplayConfigRef?) -> CGError) throws {
        var config: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&config)
        guard error == .success else {
            configurationStalled = error == .cannotComplete || error.rawValue == 1014
            throw failure("无法开始显示配置：\(error.rawValue)")
        }
        error = body(config)
        if error == .success {
            error = CGCompleteDisplayConfiguration(config, .forSession)
        } else {
            CGCancelDisplayConfiguration(config)
        }
        if error != .success {
            configurationStalled = error == .cannotComplete || error.rawValue == 1014
            throw failure(configurationStalled ? "系统显示配置无响应，请注销或重启 Mac。" : "显示配置失败：\(error.rawValue)")
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "PadDisplay", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
