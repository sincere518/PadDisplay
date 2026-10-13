// P0 探测：每秒记录 UU 被控相关信号，只在变化时打印，用于对比连入/断开
// 信号：① UURemoteServer 覆盖窗口 ② UU 主窗口是否存在 ③ 主窗口内被控文字与控制端设备名 ④ 被控端日志修改时间
import AppKit
import ApplicationServices

func attr(_ el: AXUIElement, _ n: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil
}

func overlayWindows() -> String {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let ws = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "UURemoteServer" }
    return ws.map { w -> String in
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let on = (w[kCGWindowIsOnscreen as String] as? Bool) == true ? "on" : "off"
        return "\(b["Width"] ?? 0)x\(b["Height"] ?? 0)@\(b["X"] ?? 0),\(b["Y"] ?? 0)/\(on)"
    }.sorted().joined(separator: " ")
}

/// 主窗口里「本机被控中」区域的文字（表格行 = 控制端设备）
func controlledInfo() -> String {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.uuremote").first else { return "UU未运行" }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    guard let wins = attr(ax, kAXWindowsAttribute) as? [AXUIElement], !wins.isEmpty else { return "主窗口=无" }
    var texts: [String] = []
    var rows: [String] = []
    func walk(_ el: AXUIElement, inRow: Bool, depth: Int = 0) {
        guard depth < 25 else { return }  // AX 树可能有环
        let role = attr(el, kAXRoleAttribute) as? String
        if role == kAXStaticTextRole, let v = attr(el, kAXValueAttribute) as? String {
            if inRow { rows.append(v) } else if v.contains("被控") || v.contains("控制此电脑") { texts.append(v) }
        }
        for k in (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(k, inRow: inRow || role == kAXRowRole, depth: depth + 1) }
    }
    wins.forEach { walk($0, inRow: false) }
    let rowText = rows.filter { !$0.hasPrefix("连接时长") }.joined(separator: "|")
    return "主窗口=有 文字=[\(Array(Set(texts)).sorted().joined(separator: "; "))] 控制端=[\(rowText)]"
}

func logMtime() -> String {
    let p = "/Users/Shared/UURemote/\(getuid())/com.netease.uuremote.server/Logs/Streamer/connection_log_controlled.slog"
    let d = (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date
    return d.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
}

let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss"
var last: [String] = []
setvbuf(stdout, nil, _IOLBF, 0)
print("\(fmt.string(from: Date())) 开始记录（AX 权限：\(AXIsProcessTrusted())）")
while true {
    let cur = ["覆盖窗口: " + overlayWindows(), controlledInfo(), "日志mtime: " + logMtime()]
    for (i, s) in cur.enumerated() where last.count != cur.count || last[i] != s {
        print("\(fmt.string(from: Date())) \(s)")
    }
    last = cur
    Thread.sleep(forTimeInterval: 1)
}
