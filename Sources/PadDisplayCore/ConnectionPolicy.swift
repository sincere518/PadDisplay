import Foundation

public enum UUControllerParser {
    public static func name(in fields: [String]) -> String? {
        let fields = fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if fields.contains("远程控制") {
            return fields.first { $0 != "远程控制" && !$0.hasPrefix("连接时长") }
        }
        let row = fields.joined(separator: " ")
        guard let marker = row.range(of: #"\s+远程控制\s+连接时长(?:\s+\d+:\d{2}:\d{2})?\s*$"#,
                                     options: .regularExpression) else { return nil }
        let name = row[..<marker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// 明确断开等 3 秒；暂时读不到界面等 15 秒。失效的旧结果不能无限保留屏幕。
public struct ConnectionTracker {
    public private(set) var names: [String] = []
    private var lastConfirmed = Date.distantPast
    private var emptySince: Date?

    public init() {}

    @discardableResult
    public mutating func update(_ observed: [String]?, now: Date) -> [String] {
        if let observed, !observed.isEmpty {
            names = Array(Set(observed)).sorted()
            lastConfirmed = now
            emptySince = nil
        } else if observed != nil {
            if emptySince == nil { emptySince = now }
            if now.timeIntervalSince(emptySince!) >= 3 { names = [] }
        } else if now.timeIntervalSince(lastConfirmed) >= 15 {
            names = []
        }
        return names
    }
}

public enum DeviceDecision: Equatable {
    case idle
    case use(DeviceProfile)
    case configure(String)
    case simultaneous

    public static func resolve(names: [String], profiles: [DeviceProfile]) -> DeviceDecision {
        guard !names.isEmpty else { return .idle }
        guard names.count == 1 else { return .simultaneous }
        let name = names[0]
        guard let profile = profiles.first(where: { $0.name == name }) else { return .configure(name) }
        return profile.enabled ? .use(profile) : .idle
    }
}
