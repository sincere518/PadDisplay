import Foundation

public struct ProfileArchive: Codable {
    public let format: Int
    public let profiles: [DeviceProfile]

    public init(profiles: [DeviceProfile]) { format = 1; self.profiles = profiles }

    public func merged(with existing: [DeviceProfile], replace: Bool) throws -> [DeviceProfile] {
        var next = replace ? profiles : existing
        if !replace {
            for var profile in profiles {
                if let index = next.firstIndex(where: { $0.name == profile.name || $0.id == profile.id }) {
                    profile.id = next[index].id
                    next[index] = profile
                } else { next.append(profile) }
            }
        }
        _ = try Self.read(JSONEncoder().encode(Self(profiles: next)))
        return next
    }

    public static func read(_ data: Data, allowingEmpty: Bool = false) throws -> ProfileArchive {
        guard data.count <= 1_048_576 else { throw invalid("配置文件不能超过 1 MB。") }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.format == 1 else { throw invalid("不支持此配置文件版本。") }
        guard (allowingEmpty || !archive.profiles.isEmpty), archive.profiles.count <= 100 else { throw invalid("配置需包含 1 至 100 台设备。") }
        var ids = Set<UUID>(), names = Set<String>(), serials = Set<UInt32>()
        for profile in archive.profiles {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 128, name == profile.name else { throw invalid("设备名称无效。") }
            guard ids.insert(profile.id).inserted, names.insert(name).inserted,
                  serials.insert(profile.displaySerial).inserted else { throw invalid("配置包含重复设备或屏幕身份。") }
            // 允许导出尚未填写尺寸的禁用草稿，启用的设备必须完全有效。
            if profile.enabled, let error = profile.validationError { throw invalid("\(name)：\(error)") }
        }
        return archive
    }

    private static func invalid(_ text: String) -> NSError {
        NSError(domain: "PadDisplay.Configuration", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
