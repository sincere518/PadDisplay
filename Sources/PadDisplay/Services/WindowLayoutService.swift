import AppKit
import ApplicationServices
import CryptoKit

struct SavedWindow: Codable, Equatable {
    let pid: pid_t
    let bundleID: String
    let identifier: String?
    let titleDigest: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// 只还原仍存在的普通窗口；窗口标题只保存摘要，不进入恢复日志。
final class WindowLayoutService {
    private var live: [(SavedWindow, AXUIElement)] = []

    func capture() -> [SavedWindow] {
        live = []
        guard AXIsProcessTrusted() else { return [] }
        let deadline = Date().addingTimeInterval(3)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard Date() < deadline, live.count < 200 else { break }
            guard let bundleID = app.bundleIdentifier else { continue }
            for window in windows(app.processIdentifier) {
                guard Date() < deadline, live.count < 200 else { break }
                guard normal(window), let origin = point(window), let size = size(window) else { continue }
                live.append((SavedWindow(pid: app.processIdentifier, bundleID: bundleID,
                                         identifier: value(window, kAXIdentifierAttribute) as? String,
                                         titleDigest: digest(window), x: origin.x, y: origin.y,
                                         width: size.width, height: size.height), window))
            }
        }
        return live.map(\.0)
    }

    func restore(_ saved: [SavedWindow]) -> Int {
        guard AXIsProcessTrusted() else { return saved.count }
        var skipped = 0
        let deadline = Date().addingTimeInterval(4)
        for (index, record) in saved.enumerated() {
            guard let app = NSRunningApplication(processIdentifier: record.pid), app.bundleIdentifier == record.bundleID else { continue }
            guard Date() < deadline else { skipped += 1; continue }
            let window: AXUIElement?
            if live.indices.contains(index), live[index].0 == record {
                window = live[index].1
            } else {
                let matches = windows(record.pid).filter { candidate in
                    if let identifier = record.identifier, !identifier.isEmpty {
                        return value(candidate, kAXIdentifierAttribute) as? String == identifier
                    }
                    return !record.titleDigest.isEmpty && digest(candidate) == record.titleDigest
                }
                window = matches.count == 1 ? matches.first : nil
            }
            guard let window, normal(window), (1...32768).contains(record.width), (1...32768).contains(record.height),
                  (-1_000_000...1_000_000).contains(record.x), (-1_000_000...1_000_000).contains(record.y) else { skipped += 1; continue }
            if let origin = point(window), let size = size(window),
               abs(origin.x - record.x) < 2, abs(origin.y - record.y) < 2,
               abs(size.width - record.width) < 2, abs(size.height - record.height) < 2 { continue }
            var position = CGPoint(x: record.x, y: record.y), size = CGSize(width: record.width, height: record.height)
            guard let p = AXValueCreate(.cgPoint, &position), let s = AXValueCreate(.cgSize, &size) else { skipped += 1; continue }
            let sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
            let positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
            guard sizeError == .success, positionError == .success, let origin = point(window), let restoredSize = self.size(window),
                  abs(origin.x - record.x) < 2, abs(origin.y - record.y) < 2,
                  abs(restoredSize.width - record.width) < 2, abs(restoredSize.height - record.height) < 2 else {
                skipped += 1; continue
            }
        }
        live = []
        return skipped
    }

    private func windows(_ pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        return value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
    }

    private func normal(_ window: AXUIElement) -> Bool {
        value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole &&
        value(window, kAXMinimizedAttribute) as? Bool != true && value(window, "AXFullScreen") as? Bool != true
    }

    private func digest(_ window: AXUIElement) -> String {
        guard let title = value(window, kAXTitleAttribute) as? String, !title.isEmpty else { return "" }
        return SHA256.hash(data: Data(title.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func point(_ window: AXUIElement) -> CGPoint? {
        guard let value = value(window, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &result) ? result : nil
    }

    private func size(_ window: AXUIElement) -> CGSize? {
        guard let value = value(window, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &result) ? result : nil
    }
}
