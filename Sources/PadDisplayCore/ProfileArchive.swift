import Foundation

public struct ProfileArchive: Codable {
    public let format: Int
    public let profiles: [DeviceProfile]

    public init(profiles: [DeviceProfile]) { format = 1; self.profiles = profiles }

    public func merged(with existing: [DeviceProfile], replace: Bool) throws -> [DeviceProfile] {
        _ = try Self.read(JSONEncoder().encode(self))
        if replace { return profiles }
        var next = existing
        var updated = Set<Int>()
        for var profile in profiles {
            let matches = existing.indices.filter {
                existing[$0].name == profile.name || existing[$0].id == profile.id
            }
            guard matches.count <= 1 else {
                throw Self.invalid("设备「\(profile.name)」的名称和屏幕身份对应不同的本机配置，无法合并。")
            }
            guard let index = matches.first else { next.append(profile); continue }
            guard updated.insert(index).inserted else {
                throw Self.invalid("导入文件中有多台设备对应同一项本机配置，无法合并。")
            }
            profile.id = existing[index].id
            next[index] = profile
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
