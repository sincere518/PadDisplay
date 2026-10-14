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
    public var density: DesktopDensity
    public var region: DisplayRegion
    public var role: DisplayRole
    public var favorite: Bool

    public var displaySerial: UInt32 {
        // UUID 的确定性摘要；不使用每次进程启动都会变化的 Swift Hasher。
        let hash = id.uuidString.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return hash == 0 ? 1 : hash
    }

    public var effectiveSpec: DisplaySpec {
        guard (0...8192).contains(spec.width), (0...8192).contains(spec.height) else { return spec }
        let scale = density.scale
        let width = Double(spec.width) * region.widthFraction * scale
        let height = Double(spec.height) * scale
        let step = spec.hiDPI ? 2.0 : 1.0
        return DisplaySpec(width: Int((width / step).rounded()) * Int(step),
                           height: Int((height / step).rounded()) * Int(step), hiDPI: spec.hiDPI)
    }

    public var validationError: String? {
        spec.validationError ?? effectiveSpec.validationError
    }

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, spec: DisplaySpec) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.spec = spec
        density = .standard
        region = .full
        role = .main
        favorite = true
    }

    private enum CodingKeys: String, CodingKey { case id, name, enabled, spec, density, region, role, favorite }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        spec = try values.decode(DisplaySpec.self, forKey: .spec)
        density = try values.decodeIfPresent(DesktopDensity.self, forKey: .density) ?? .standard
        region = try values.decodeIfPresent(DisplayRegion.self, forKey: .region) ?? .full
        role = try values.decodeIfPresent(DisplayRole.self, forKey: .role) ?? .main
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? true
    }

    public func applyingSizeInput(width: String, height: String) -> DeviceProfile? {
        guard enabled else { return self }
        guard let w = Int(width), let h = Int(height) else { return nil }
        var value = self
        value.spec.width = w
        value.spec.height = h
        return value
    }

    public static func draft(for name: String) -> DeviceProfile {
        let preset = ScreenPreset.suggested(for: name)
        return DeviceProfile(name: name, enabled: false, spec: preset?.spec ?? DisplaySpec(width: 0, height: 0))
    }
}

public enum DesktopDensity: String, Codable, CaseIterable {
    case standard, largerText, moreSpace
    public var label: String {
        switch self { case .standard: "标准"; case .largerText: "更大文字"; case .moreSpace: "更多空间" }
    }
    public var scale: Double {
        switch self { case .standard: 1; case .largerText: 0.8; case .moreSpace: 1.25 }
    }
}

public enum DisplayRegion: String, Codable, CaseIterable {
    case full, twoThirds, half
    public var label: String {
        switch self { case .full: "完整屏幕"; case .twoThirds: "约 ⅔ 宽度"; case .half: "约 ½ 宽度" }
    }
    public var widthFraction: Double {
        switch self { case .full: 1; case .twoThirds: 2.0 / 3; case .half: 0.5 }
    }
}

public enum DisplayRole: String, Codable, CaseIterable {
    case main, extended
    public var label: String { self == .main ? "主显示器" : "扩展显示器" }
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
