// 设备类型、分辨率预设与配置持久化
import Foundation

enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case computer, tablet, phone
    var id: String { rawValue }
    var label: String {
        switch self {
        case .computer: return "电脑"
        case .tablet: return "平板"
        case .phone: return "手机"
        }
    }
}

/// 横屏原生像素
struct Preset: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: DeviceKind
    let width: Int
    let height: Int
    var label: String { "\(name)  \(width)×\(height)" }
}

enum Presets {
    static let customID = "custom"

    // 2026-10 联网核实：OPPO 官方规格页、Apple 技术规格页、GSMArena
    static let all: [Preset] = [
        Preset(id: "oppo-pad-3-pro", name: "OPPO Pad 3 Pro", kind: .tablet, width: 3000, height: 2120),
        Preset(id: "ipad-air-11", name: "iPad Air 11 英寸", kind: .tablet, width: 2360, height: 1640),
        Preset(id: "ipad-air-13", name: "iPad Air 13 英寸", kind: .tablet, width: 2732, height: 2048),
        Preset(id: "ipad-pro-11", name: "iPad Pro 11 英寸", kind: .tablet, width: 2420, height: 1668),
        Preset(id: "ipad-pro-13", name: "iPad Pro 13 英寸", kind: .tablet, width: 2752, height: 2064),
        Preset(id: "ipad-mini", name: "iPad mini", kind: .tablet, width: 2266, height: 1488),
        Preset(id: "iphone-17", name: "iPhone 17", kind: .phone, width: 2622, height: 1206),
        Preset(id: "oppo-reno13-pro", name: "OPPO Reno13 Pro", kind: .phone, width: 2800, height: 1272),
        Preset(id: "android-20x9", name: "其他安卓手机（20:9）", kind: .phone, width: 2400, height: 1080),
    ]

    static func preset(id: String?) -> Preset? { all.first { $0.id == id } }

    /// 按 UU 中的设备名猜测预设
    static func guess(name: String, kind: DeviceKind) -> Preset? {
        let n = name.lowercased()
        let rules: [(String, String)] = [
            ("pad 3 pro", "oppo-pad-3-pro"), ("ipad air", "ipad-air-11"), ("ipad pro", "ipad-pro-11"),
            ("ipad mini", "ipad-mini"), ("iphone", "iphone-17"), ("reno13 pro", "oppo-reno13-pro"),
        ]
        if let hit = rules.first(where: { n.contains($0.0) }), let p = preset(id: hit.1), p.kind == kind { return p }
        switch kind {
        case .tablet: return preset(id: "ipad-air-11")
        case .phone: return preset(id: "android-20x9")
        case .computer: return nil
        }
    }

    /// 首次配置时的类型预填：UU「电脑」组 → 电脑；名称含 iPad/Pad → 平板；其余 → 手机
    static func guessKind(name: String, isComputerGroup: Bool) -> DeviceKind {
        if isComputerGroup { return .computer }
        return name.lowercased().contains("pad") ? .tablet : .phone
    }
}

struct DeviceConfig: Codable, Identifiable, Hashable {
    var name: String
    var kind: DeviceKind
    var presetID: String?
    var width: Int
    var height: Int
    var hiDPI: Bool = true
    var id: String { name }

    var sizeLabel: String { "\(width)×\(height)\(hiDPI ? " 高清" : "")" }

    static func make(name: String, kind: DeviceKind) -> DeviceConfig {
        let p = Presets.guess(name: name, kind: kind)
        return DeviceConfig(name: name, kind: kind, presetID: p?.id, width: p?.width ?? 2360, height: p?.height ?? 1640)
    }
}

struct AppConfig: Codable {
    var devices: [DeviceConfig] = []
    var defaultDevice: String?
    var lastDevice: String?
    var paused = false
    /// 远程时关闭物理屏（缺省关闭，在设置里开启；可选类型以兼容旧配置文件）
    var disablePhysical: Bool?
    var shouldDisablePhysical: Bool { disablePhysical ?? false }
    /// 看门狗（兜底恢复物理屏）缺省关闭，只有用户在设置里开启才安装
    var watchdogEnabled: Bool?
    var shouldRunWatchdog: Bool { watchdogEnabled ?? false }
    /// 是否已看过首次启动功能导览
    var tourShown: Bool?
}

final class ConfigStore {
    static let shared = ConfigStore()

    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("UUDisplay", isDirectory: true)
    private let url = ConfigStore.dir.appendingPathComponent("config.json")

    var config: AppConfig {
        didSet { save() }
    }

    var isConfigured: Bool { !config.devices.isEmpty }

    private init() {
        try? FileManager.default.createDirectory(at: ConfigStore.dir, withIntermediateDirectories: true)
        config = (try? JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))) ?? AppConfig()
    }

    func device(named name: String?) -> DeviceConfig? {
        guard let name else { return nil }
        return config.devices.first { $0.name == name }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(config).write(to: url, options: .atomic)
    }
}
