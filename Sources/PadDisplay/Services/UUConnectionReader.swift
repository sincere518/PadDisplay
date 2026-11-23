import AppKit
import ApplicationServices
import PadDisplayCore

struct ConnectionReading {
    var controllers: [String]?
    var detail: String
    var controllerCount: Int? = nil
}

/// 只读取 UU 自己的被控设备表格，不依赖远控覆盖窗口是否出现。
final class UUConnectionReader {
    static var authorized: Bool { AXIsProcessTrusted() }
    private let queue = DispatchQueue(label: "local.PadDisplay.connection")
    private var inFlight = false
    private var waiting: [(ConnectionReading) -> Void] = []

    func sample(_ completion: @escaping (ConnectionReading) -> Void) {
        guard !inFlight else {
            waiting.append(completion)
            return
        }
        guard Self.authorized else {
            completion(.init(controllers: nil, detail: "需要授权识别连接设备"))
            return
        }
        inFlight = true
        queue.async {
            let reading = Self.read()
            DispatchQueue.main.async {
                let waiting = self.waiting
                self.waiting.removeAll()
                self.inFlight = false
                completion(reading)
                waiting.forEach { $0(reading) }
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String, until deadline: Date) -> AnyObject? {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0, AXUIElementSetMessagingTimeout(element, Float(min(0.3, remaining))) == .success else { return nil }
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func role(_ element: AXUIElement, until deadline: Date) -> String? {
        attribute(element, kAXRoleAttribute, until: deadline) as? String
    }

    private static func text(_ element: AXUIElement, until deadline: Date) -> String? {
        for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = attribute(element, key, until: deadline) as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func descendants(_ roots: [AXUIElement], deadline: Date) -> [AXUIElement]? {
        var pending = roots.map { ($0, 0) }
        var result: [AXUIElement] = []
        var seen = Set<AXUIElement>()
        while let (element, depth) = pending.popLast() {
            guard seen.insert(element).inserted else { continue }
            guard result.count < 1500, Date() < deadline else { return nil }
            result.append(element)
            if let children = attribute(element, kAXChildrenAttribute, until: deadline) as? [AXUIElement], !children.isEmpty {
                guard depth < 64 else { return nil }
                pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return result
    }

    private static func read() -> ConnectionReading {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.uuremote").first else {
            return .init(controllers: [], detail: "等待 UU远程启动", controllerCount: 0)
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let deadline = Date().addingTimeInterval(2)
        guard let windows = attribute(element, kAXWindowsAttribute, until: deadline) as? [AXUIElement], !windows.isEmpty else {
            return .init(controllers: nil, detail: "请打开 UU远程主界面")
        }
        let incomplete = ConnectionReading(controllers: nil, detail: "暂时未能完整读取 UU远程界面")
        guard let elements = descendants(windows, deadline: deadline) else { return incomplete }
        var names: [String] = []
        var titles: [String] = []
        for element in elements {
            guard Date() < deadline else { return incomplete }
            let elementRole = role(element, until: deadline)
            if elementRole == kAXStaticTextRole, let title = text(element, until: deadline) { titles.append(title) }
            if elementRole == kAXRowRole {
                guard let children = descendants([element], deadline: deadline) else { return incomplete }
                let fields = children.compactMap { child in
                    role(child, until: deadline) == kAXStaticTextRole ? text(child, until: deadline) : nil
                }
                if let name = UUControllerParser.name(in: fields) { names.append(name) }
            }
        }
        guard Date() < deadline else { return incomplete }
        let count = UUControllerParser.controllerCount(in: titles)
        if count == 0 {
            guard names.isEmpty else {
                return .init(controllers: nil, detail: "UU 连接数量与设备列表不一致，正在重新检查", controllerCount: names.count)
            }
            return .init(controllers: [], detail: "等待远程设备连接", controllerCount: 0)
        }
        if !names.isEmpty {
            return .init(controllers: Array(Set(names)).sorted(), detail: "已识别连接设备", controllerCount: max(count ?? 0, names.count))
        }
        if (count ?? 0) > 0 || titles.contains(where: { $0.contains("本机被控中") && !$0.contains("当前有 0 台") }) {
            return .init(controllers: nil, detail: "UU 正在被控，但尚未读到设备名称", controllerCount: count)
        }
        if titles.contains(where: { $0.contains("无法连接至服务器") || $0.contains("无法连接到服务器") }) {
            return .init(controllers: nil, detail: "UU界面显示无法连接服务器，尚未读到被控设备。")
        }
        return .init(controllers: nil, detail: "尚未读到 UU 的连接状态，请保持主界面可读取")
    }
}
