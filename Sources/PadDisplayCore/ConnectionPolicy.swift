import Foundation

public enum UUControllerParser {
    private static let countPattern = try! NSRegularExpression(pattern: #"当前有\s*(\d+)\s*台设备正在控制此电脑"#)

    public static func controllerCount(in headers: [String]) -> Int? {
        headers.compactMap { header -> Int? in
            guard let match = countPattern.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
                  let range = Range(match.range(at: 1), in: header) else { return nil }
            return Int(header[range])
        }.max()
    }

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
    public private(set) var controllerCount = 0
    private var lastConfirmed = Date.distantPast
    private var emptySince: Date?

    public init() {}

    @discardableResult
    public mutating func update(_ observed: [String]?, reportedCount: Int?, now: Date) -> [String] {
        if let observed, !observed.isEmpty {
            names = Array(Set(observed)).sorted()
            controllerCount = max(reportedCount ?? names.count, names.count)
            lastConfirmed = now
            emptySince = nil
        } else if observed != nil, (reportedCount ?? 0) == 0 {
            if emptySince == nil { emptySince = now }
            if now.timeIntervalSince(emptySince!) >= 3 { names = []; controllerCount = 0 }
        } else if now.timeIntervalSince(lastConfirmed) >= 15 {
            names = []
            controllerCount = reportedCount ?? 0
        } else if let reportedCount, reportedCount > 0 {
            if controllerCount != reportedCount { names = [] }
            controllerCount = reportedCount
        }
        return names
    }
}

public enum DeviceDecision: Equatable {
    case idle
    case use(DeviceProfile)
    case configure(String)
    case simultaneous

    public static func resolve(names: [String], controllerCount: Int, profiles: [DeviceProfile]) -> DeviceDecision {
        guard controllerCount <= 1 else { return .simultaneous }
        guard !names.isEmpty else { return .idle }
        guard names.count == 1 else { return .simultaneous }
        let name = names[0]
        guard let profile = profiles.first(where: { $0.name == name }) else { return .configure(name) }
        return profile.enabled ? .use(profile) : .idle
    }
}
