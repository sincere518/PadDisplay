import CoreGraphics
import Foundation

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
