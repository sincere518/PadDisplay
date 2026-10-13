import CoreGraphics
import DisplayBridge
import Foundation
import PadDisplayCore

struct DisplayRequest: Equatable {
    let name: String
    let spec: DisplaySpec
}

struct DisplayReport {
    var active: DisplayRequest?
    var busy = false
    var message = "尚未创建远程屏幕"
    var failed = false
    var recoveryNeeded = false
}

private struct SavedPosition: Codable {
    let id: CGDirectDisplayID
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let x: Int32
    let y: Int32
}

/// 拓扑操作全部串行执行；新建与释放至少间隔 3 秒，主线程保持响应。
final class VirtualDisplayService {
    static let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PadDisplay", isDirectory: true)
    private let queue = DispatchQueue(label: "local.PadDisplay.displays")
    private let journal = VirtualDisplayService.supportDirectory.appendingPathComponent("display-session.json")
    private var desired: DisplayRequest?
    private var current: DisplayRequest?
    private var busy = false
    private var blocked = false
    private var needsRecovery = false
    private var quitCompletion: (() -> Void)?
    // 以下数据只在 queue 上访问。
    private var handle: UnsafeMutableRawPointer?
    private var born = Date.distantPast
    private var positions: [SavedPosition] = []
    private var configurationStalled = false
    var onChange: ((DisplayReport) -> Void)?

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
        let changed = desired != value
        desired = value
        if retry || changed { blocked = false }
        reconcile()
    }

    func shutdown(_ completion: @escaping () -> Void) {
        quitCompletion = completion
        request(nil, retry: true)
    }

    func recover() {
        busy = true
        queue.async {
            var error: Error?
            do {
                if FileManager.default.fileExists(atPath: self.journal.path) {
                    self.positions = try JSONDecoder().decode([SavedPosition].self, from: Data(contentsOf: self.journal))
                    try self.restorePositions()
                }
            } catch let failure { error = failure }
            DispatchQueue.main.async {
                self.busy = false
                self.blocked = error != nil
                self.needsRecovery = error != nil
                self.onChange?(.init(message: error?.localizedDescription ?? "准备就绪", failed: error != nil,
                                    recoveryNeeded: error != nil))
                self.reconcile()
            }
        }
    }

    private func reconcile() {
        guard !busy else { return }
        if desired == current && !(desired == nil && needsRecovery) {
            if desired == nil, let done = quitCompletion { quitCompletion = nil; done() }
            return
        }
        guard !blocked else { return }
        let target = desired
        let previous = current
        busy = true
        onChange?(.init(active: current, busy: true, message: target == nil ? "正在恢复原桌面…" : "正在准备远程屏幕…"))
        queue.async {
            var result = DisplayReport()
            do {
                if self.handle != nil || !self.positions.isEmpty || FileManager.default.fileExists(atPath: self.journal.path) {
                    try self.remove()
                }
                if let target {
                    try self.create(target)
                    result.active = target
                    result.message = "远程屏幕已就绪：\(target.spec.label)"
                } else { result.message = "已恢复原桌面" }
            } catch {
                // 配置事务无响应时不继续变更拓扑；其他失败尝试正常收尾。
                if !self.configurationStalled { try? self.remove() }
                result.active = self.handle == nil ? nil : target ?? previous
                result.message = error.localizedDescription
                result.failed = true
            }
            let pendingRecovery = self.handle != nil || !self.positions.isEmpty || FileManager.default.fileExists(atPath: self.journal.path)
            result.recoveryNeeded = result.failed && pendingRecovery
            DispatchQueue.main.async {
                self.busy = false
                self.current = result.active
                self.blocked = result.failed
                self.needsRecovery = result.failed && pendingRecovery
                self.onChange?(result)
                if result.failed, let done = self.quitCompletion { self.quitCompletion = nil; done() }
                if !result.failed { self.reconcile() }
            }
        }
    }

    private func create(_ request: DisplayRequest) throws {
        if let problem = request.spec.validationError { throw failure(problem) }
        positions = try Self.readOnlineDisplays().map { id in
            let origin = CGDisplayBounds(id).origin
            return SavedPosition(id: id, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                 serial: CGDisplaySerialNumber(id), x: Int32(origin.x), y: Int32(origin.y))
        }
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(positions).write(to: journal, options: .atomic)
        let spec = request.spec
        handle = PDDisplayCreate("PadDisplay · \(request.name)", UInt32(spec.width), UInt32(spec.height))
        born = Date()
        guard let handle else { throw failure("系统没有成功创建虚拟屏幕。") }
        guard PDDisplayApply(handle, UInt32(spec.width), UInt32(spec.height), spec.hiDPI) else {
            throw failure("系统未接受此分辨率，请检查尺寸或关闭高清模式后重试。")
        }
        let id = PDDisplayID(handle)
        Thread.sleep(forTimeInterval: 3)
        guard try Self.readOnlineDisplays().contains(id), let mode = CGDisplayCopyDisplayMode(id),
              mode.pixelWidth == spec.width, mode.pixelHeight == spec.height else {
            throw failure("虚拟屏幕未以目标分辨率上线。")
        }
        let origin = CGDisplayBounds(id).origin
        let online = try Self.readOnlineDisplays()
        try configure { config in
            for display in online {
                let p = CGDisplayBounds(display).origin
                let error = CGConfigureDisplayOrigin(config, display, Int32(p.x - origin.x), Int32(p.y - origin.y))
                if error != .success { return error }
            }
            return .success
        }
        Thread.sleep(forTimeInterval: 0.7)
        guard CGMainDisplayID() == id else { throw failure("虚拟屏幕已创建，但未成为主显示器。") }
    }

    private func remove() throws {
        if configurationStalled { throw failure("系统显示配置无响应，请注销或重启 Mac 后恢复。") }
        if positions.isEmpty, FileManager.default.fileExists(atPath: journal.path) {
            positions = try JSONDecoder().decode([SavedPosition].self, from: Data(contentsOf: journal))
        }
        if let handle {
            Thread.sleep(forTimeInterval: max(0, 3 - Date().timeIntervalSince(born)))
            let id = PDDisplayID(handle)
            PDDisplayRelease(handle)
            self.handle = nil
            Thread.sleep(forTimeInterval: 1.5)
            guard try !Self.readOnlineDisplays().contains(id) else { throw failure("虚拟屏幕尚未移除，请稍后重试恢复。") }
        }
        try restorePositions()
    }

    private func restorePositions() throws {
        let available = positions.isEmpty ? [] : Set(try Self.readOnlineDisplays())
        let targets = positions.filter { p in
            available.contains(p.id) && CGDisplayVendorNumber(p.id) == p.vendor &&
            CGDisplayModelNumber(p.id) == p.model && CGDisplaySerialNumber(p.id) == p.serial
        }
        if !targets.isEmpty {
            try configure { config in
                for p in targets {
                    let error = CGConfigureDisplayOrigin(config, p.id, p.x, p.y)
                    if error != .success { return error }
                }
                return .success
            }
            Thread.sleep(forTimeInterval: 0.7)
        }
        positions = []
        if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }
    }

    private func configure(_ body: (CGDisplayConfigRef?) -> CGError) throws {
        var config: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&config)
        guard error == .success else {
            configurationStalled = error == .cannotComplete || error.rawValue == 1014
            throw failure("无法开始显示配置：\(error.rawValue)")
        }
        error = body(config)
        if error == .success { error = CGCompleteDisplayConfiguration(config, .forSession) }
        if error != .success {
            CGCancelDisplayConfiguration(config)
            configurationStalled = error == .cannotComplete || error.rawValue == 1014
            throw failure(configurationStalled ? "系统显示配置无响应，请注销或重启 Mac。" : "显示配置失败：\(error.rawValue)")
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "PadDisplay", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
