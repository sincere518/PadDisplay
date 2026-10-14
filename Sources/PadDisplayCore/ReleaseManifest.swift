import Foundation

public struct ReleaseManifest: Codable, Equatable {
    public let version: String
    public let build: Int
    public let minimumSystemVersion: String
    public let downloadURL: URL
    public let sha256: String
    public let notes: String

    public func validate() throws {
        guard !VersionNumber(version).parts.isEmpty, build > 0, !VersionNumber(minimumSystemVersion).parts.isEmpty,
              Self.secureURL(downloadURL), sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit && $0.isASCII }), notes.count <= 20_000 else {
            throw NSError(domain: "PadDisplay.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "更新描述文件无效。"])
        }
    }

    public func isNewer(than version: String, build: Int) -> Bool {
        let next = VersionNumber(self.version), current = VersionNumber(version)
        return next > current || (next == current && self.build > build)
    }

    public static func secureURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
}

public struct VersionNumber: Comparable {
    public let parts: [Int]
    public init(_ text: String) {
        let fields = (text.hasPrefix("v") ? String(text.dropFirst()) : text).split(separator: ".", omittingEmptySubsequences: false)
        if (1...4).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && Int($0) != nil }) {
            var values = fields.compactMap { Int($0) }
            while values.count > 1 && values.last == 0 { values.removeLast() }
            parts = values
        } else { parts = [] }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0, r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}
