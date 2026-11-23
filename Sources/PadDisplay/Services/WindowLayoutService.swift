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
            for window in windows(app.processIdentifier, before: deadline) {
                guard Date() < deadline, live.count < 200 else { break }
                guard normal(window, before: deadline), let origin = point(window, before: deadline),
                      let size = size(window, before: deadline) else { continue }
                live.append((SavedWindow(pid: app.processIdentifier, bundleID: bundleID,
                                         identifier: value(window, kAXIdentifierAttribute, before: deadline) as? String,
                                         titleDigest: digest(window, before: deadline), x: origin.x, y: origin.y,
                                         width: size.width, height: size.height), window))
            }
        }
        return live.map(\.0)
    }

    func restore(_ saved: [SavedWindow]) -> Int {
        defer { live = [] }
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
                window = uniqueWindow(for: record, before: deadline)
            }
            guard let window, normal(window, before: deadline), (1...32768).contains(record.width), (1...32768).contains(record.height),
                  (-1_000_000...1_000_000).contains(record.x), (-1_000_000...1_000_000).contains(record.y) else { skipped += 1; continue }
            if let origin = point(window, before: deadline), let size = size(window, before: deadline),
               abs(origin.x - record.x) < 2, abs(origin.y - record.y) < 2,
               abs(size.width - record.width) < 2, abs(size.height - record.height) < 2 { continue }
            var position = CGPoint(x: record.x, y: record.y), size = CGSize(width: record.width, height: record.height)
            guard let p = AXValueCreate(.cgPoint, &position), let s = AXValueCreate(.cgSize, &size) else { skipped += 1; continue }
            let sized = setValue(window, kAXSizeAttribute, s, before: deadline)
            let positioned = setValue(window, kAXPositionAttribute, p, before: deadline)
            guard sized, positioned, let origin = point(window, before: deadline),
                  let restoredSize = self.size(window, before: deadline),
                  abs(origin.x - record.x) < 2, abs(origin.y - record.y) < 2,
                  abs(restoredSize.width - record.width) < 2, abs(restoredSize.height - record.height) < 2 else {
                skipped += 1; continue
            }
        }
        return skipped
    }

    private func uniqueWindow(for record: SavedWindow, before deadline: Date) -> AXUIElement? {
        var match: AXUIElement?
        for candidate in windows(record.pid, before: deadline) {
            guard Date() < deadline else { return nil }
            let matches: Bool
            if let identifier = record.identifier, !identifier.isEmpty {
                matches = value(candidate, kAXIdentifierAttribute, before: deadline) as? String == identifier
            } else {
                matches = !record.titleDigest.isEmpty && digest(candidate, before: deadline) == record.titleDigest
            }
            if matches {
                guard match == nil else { return nil }
                match = candidate
            }
        }
        return Date() < deadline ? match : nil
    }

    private func windows(_ pid: pid_t, before deadline: Date) -> [AXUIElement] {
        value(AXUIElementCreateApplication(pid), kAXWindowsAttribute, before: deadline) as? [AXUIElement] ?? []
    }

    private func setTimeout(_ element: AXUIElement, before deadline: Date) -> Bool {
        let remaining = deadline.timeIntervalSinceNow
        return remaining > 0 && AXUIElementSetMessagingTimeout(element, Float(min(0.1, remaining))) == .success
    }

    private func value(_ element: AXUIElement, _ key: String, before deadline: Date) -> CFTypeRef? {
        guard setTimeout(element, before: deadline) else { return nil }
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
    }

    private func setValue(_ element: AXUIElement, _ key: String, _ value: CFTypeRef, before deadline: Date) -> Bool {
        setTimeout(element, before: deadline) && AXUIElementSetAttributeValue(element, key as CFString, value) == .success
    }

    private func normal(_ window: AXUIElement, before deadline: Date) -> Bool {
        value(window, kAXSubroleAttribute, before: deadline) as? String == kAXStandardWindowSubrole &&
        value(window, kAXMinimizedAttribute, before: deadline) as? Bool != true &&
        value(window, "AXFullScreen", before: deadline) as? Bool != true
    }

    private func digest(_ window: AXUIElement, before deadline: Date) -> String {
        guard let title = value(window, kAXTitleAttribute, before: deadline) as? String, !title.isEmpty else { return "" }
        return SHA256.hash(data: Data(title.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func point(_ window: AXUIElement, before deadline: Date) -> CGPoint? {
        guard let value = value(window, kAXPositionAttribute, before: deadline), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &result) ? result : nil
    }

    private func size(_ window: AXUIElement, before deadline: Date) -> CGSize? {
        guard let value = value(window, kAXSizeAttribute, before: deadline), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &result) ? result : nil
    }
}
