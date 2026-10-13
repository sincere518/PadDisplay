import Foundation

public struct DisplaySpec: Codable, Equatable, Hashable {
    public var width: Int
    public var height: Int
    public var hiDPI: Bool

    public init(width: Int, height: Int, hiDPI: Bool = true) {
        self.width = width
        self.height = height
        self.hiDPI = hiDPI
    }

    public var label: String { "\(width) × \(height)" }
    public var validationError: String? {
        guard (640...8192).contains(width), (640...8192).contains(height) else {
            return "宽和高需要在 640 至 8192 像素之间。"
        }
        if hiDPI && (width % 2 != 0 || height % 2 != 0) {
            return "高清模式的宽和高需要为偶数。"
        }
        return nil
    }
}

public struct DeviceProfile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var spec: DisplaySpec

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, spec: DisplaySpec) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.spec = spec
    }
}

public struct ScreenPreset: Identifiable {
    public let id: String
    public let label: String
    public let spec: DisplaySpec

    public static let all: [ScreenPreset] = [
        .init(id: "air13", label: "iPad Air 13 英寸", spec: .init(width: 2732, height: 2048)),
        .init(id: "air11", label: "iPad Air 11 英寸", spec: .init(width: 2360, height: 1640)),
        .init(id: "pro13", label: "iPad Pro 13 英寸（M4 / M5）", spec: .init(width: 2752, height: 2064)),
        .init(id: "iphone-air", label: "iPhone Air", spec: .init(width: 2736, height: 1260)),
        .init(id: "iphone17max", label: "iPhone 17 Pro Max", spec: .init(width: 2868, height: 1320)),
    ]

    /// 只对包含明确型号、尺寸的名称预填；昵称和缺少尺寸的 iPad 保留待配置状态。
    public static func suggested(for name: String) -> ScreenPreset? {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var id: String?
        if n.contains("ipad air") {
            let thirteen = n.range(of: #"\b13\s*(英寸|寸|-inch)"#, options: .regularExpression) != nil
            let eleven = n.range(of: #"\b11\s*(英寸|寸|-inch)"#, options: .regularExpression) != nil
            if thirteen != eleven { id = thirteen ? "air13" : "air11" }
        } else if n.contains("ipad pro"), n.contains("m4") || n.contains("m5"),
                  n.range(of: #"\b13\s*(英寸|寸|-inch)"#, options: .regularExpression) != nil {
            id = "pro13"
        } else if n.range(of: #"^iphone air(?:\s*\(.*\))?$"#, options: .regularExpression) != nil {
            id = "iphone-air"
        } else if n.range(of: #"^iphone 17 pro max(?:\s*\(.*\))?$"#, options: .regularExpression) != nil {
            id = "iphone17max"
        }
        return all.first { $0.id == id }
    }
}
