// P0 探测：用辅助功能 API 导出 UU远程 各进程的窗口 / 菜单栏界面树
// 用法：uuprobe [最大深度=25]
import AppKit
import ApplicationServices

let maxDepth = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 25 : 25

let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
print("辅助功能权限：\(trusted ? "✅ 已授权" : "❌ 未授权（已弹出系统授权提示）")")
guard trusted else { exit(1) }

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func text(_ el: AXUIElement) -> String {
    let role = attr(el, kAXRoleAttribute) as? String ?? "?"
    let parts = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
        .compactMap { k -> String? in
            guard let v = attr(el, k) else { return nil }
            let s = "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : "\(k.replacingOccurrences(of: "AX", with: ""))=\(s.prefix(80))"
        }
    return ([role] + parts).joined(separator: " ")
}

var count = 0
func walk(_ el: AXUIElement, _ depth: Int) {
    count += 1
    print(String(repeating: "  ", count: depth) + text(el))
    guard depth < maxDepth, let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] else { return }
    kids.forEach { walk($0, depth + 1) }
}

let apps = NSWorkspace.shared.runningApplications.filter { ($0.bundleIdentifier ?? "").contains("uuremote") || ($0.localizedName ?? "").contains("UU") }
for app in apps {
    print("\n##### \(app.localizedName ?? "?") pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "-")")
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    count = 0
    if let wins = attr(ax, kAXWindowsAttribute) as? [AXUIElement] {
        print("-- 窗口 \(wins.count) 个"); wins.forEach { walk($0, 1) }
    }
    if let v = attr(ax, kAXExtrasMenuBarAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() {
        let extras = v as! AXUIElement
        print("-- 菜单栏图标"); walk(extras, 1)
    }
    print("-- 共 \(count) 个元素")
}
