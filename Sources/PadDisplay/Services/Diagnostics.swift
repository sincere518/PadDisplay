import CoreGraphics
import Foundation
import PadDisplayCore

enum Diagnostics {
    static func screens() -> [[String: Any]] {
        VirtualDisplayService.displays().sorted().map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            let origin = CGDisplayBounds(id).origin
            return ["id": id, "main": CGDisplayIsMain(id) != 0, "vendor": CGDisplayVendorNumber(id),
                    "pixelWidth": mode?.pixelWidth ?? 0, "pixelHeight": mode?.pixelHeight ?? 0,
                    "logicalWidth": mode?.width ?? 0, "logicalHeight": mode?.height ?? 0,
                    "x": Int(origin.x), "y": Int(origin.y)]
        }
    }

    static func write(_ value: [String: Any], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        } catch { FileHandle.standardError.write(Data("无法写入诊断结果：\(error)\n".utf8)) }
    }
}

/// 从真正的 CoreGraphics 显示模式验证两个设备尺寸及恢复结果。
final class DisplaySelfTest {
    private let display = VirtualDisplayService()
    private let output: URL
    private let completion: () -> Void
    private var stage = 0
    private var finished = false
    private var initial: [[String: Any]] = []
    private var results: [[String: Any]] = []
    private let pad = DisplayRequest(name: "iPad Air 13 测试", spec: .init(width: 2732, height: 2048))
    private let phone = DisplayRequest(name: "iPhone Air 测试", spec: .init(width: 2736, height: 1260))

    init(output: URL, completion: @escaping () -> Void) { self.output = output; self.completion = completion }

    func run() {
        initial = Diagnostics.screens()
        display.onChange = { [weak self] in self?.changed($0) }
        display.recover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in self?.finish(error: "显示器自测超时") }
    }

    private func changed(_ report: DisplayReport) {
        guard !finished, !report.busy else { return }
        if report.failed { finish(error: report.message); return }
        switch stage {
        case 0:
            stage = 1
            display.request(pad)
        case 1 where report.active == pad:
            guard verify(pad) else { finish(error: "iPad 实际显示模式不匹配"); return }
            stage = 2
            display.request(phone)
        case 2 where report.active == phone:
            guard verify(phone) else { finish(error: "iPhone 实际显示模式不匹配"); return }
            stage = 3
            display.request(nil)
        case 3 where report.active == nil:
            let final = Diagnostics.screens()
            let before = try? JSONSerialization.data(withJSONObject: initial, options: .sortedKeys)
            let after = try? JSONSerialization.data(withJSONObject: final, options: .sortedKeys)
            results.append(["stage": "restore", "screens": final, "passed": before == after])
            finish(error: before == after ? nil : "原显示器的分辨率、主屏或位置未完全恢复")
        default: break
        }
    }

    private func verify(_ request: DisplayRequest) -> Bool {
        let screens = Diagnostics.screens()
        let virtual = screens.filter { ($0["vendor"] as? UInt32) == 0x5044 }
        let actual = virtual.first
        let passed = virtual.count == 1 && actual?["pixelWidth"] as? Int == request.spec.width &&
            actual?["pixelHeight"] as? Int == request.spec.height && actual?["main"] as? Bool == true
        results.append(["stage": request.name, "screens": screens, "passed": passed])
        return passed
    }

    private func finish(error: String?) {
        guard !finished else { return }
        finished = true
        display.shutdown {
            Diagnostics.write(["success": error == nil, "error": error as Any? ?? NSNull(),
                               "timestamp": ISO8601DateFormatter().string(from: Date()),
                               "before": self.initial, "stages": self.results, "after": Diagnostics.screens()], to: self.output)
            self.completion()
        }
    }
}
