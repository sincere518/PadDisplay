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
                self.inFlight = false
                completion(reading)
                let waiting = self.waiting; self.waiting = []
                waiting.forEach { $0(reading) }
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func role(_ element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }

    private static func text(_ element: AXUIElement) -> String? {
        for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = attribute(element, key) as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func descendants(_ roots: [AXUIElement], deadline: Date) -> [AXUIElement] {
        var pending = roots.map { ($0, 0) }
        var result: [AXUIElement] = []
        while let (element, depth) = pending.popLast(), result.count < 1500, Date() < deadline {
            result.append(element)
            if depth < 20, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return result
    }

    private static func read() -> ConnectionReading {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.uuremote").first else {
            return .init(controllers: [], detail: "等待 UU远程启动")
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        let deadline = Date().addingTimeInterval(2)
        guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else {
            return .init(controllers: nil, detail: "请打开 UU远程主界面")
        }
        let elements = descendants(windows, deadline: deadline)
        var names: [String] = []
        var titles: [String] = []
        for element in elements {
            guard Date() < deadline else { return .init(controllers: nil, detail: "UU远程界面暂时无响应") }
            let elementRole = role(element)
            if elementRole == kAXStaticTextRole, let title = text(element) { titles.append(title) }
            if elementRole == kAXRowRole {
                var fields: [String] = []
                for child in descendants([element], deadline: deadline) {
                    guard Date() < deadline else { return .init(controllers: nil, detail: "UU远程界面暂时无响应") }
                    if role(child) == kAXStaticTextRole, let field = text(child) { fields.append(field) }
                }
                if let name = UUControllerParser.name(in: fields), !names.contains(name) { names.append(name) }
            }
        }
        guard Date() < deadline else { return .init(controllers: nil, detail: "UU远程界面暂时无响应") }
        let count = UUControllerParser.controllerCount(in: titles)
        if count == 0 { return .init(controllers: [], detail: "等待远程设备连接", controllerCount: 0) }
        if !names.isEmpty { return .init(controllers: names, detail: "已识别连接设备", controllerCount: count) }
        if (count ?? 0) > 0 || titles.contains(where: { $0.contains("本机被控中") && !$0.contains("当前有 0 台") }) {
            return .init(controllers: nil, detail: "UU 正在被控，但尚未读到设备名称", controllerCount: count)
        }
        if titles.contains(where: { $0.contains("无法连接至服务器") || $0.contains("无法连接到服务器") }) {
            return .init(controllers: nil, detail: "UU界面显示无法连接服务器，尚未读到被控设备。")
        }
        return .init(controllers: [], detail: "等待远程设备连接")
    }
}
