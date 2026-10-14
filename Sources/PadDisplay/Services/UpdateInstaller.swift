import Foundation
import PadDisplayCore
import Security

enum UpdateInstaller {
    static func unpack(_ archive: URL, into directory: URL) throws -> URL {
        let paths = try run("/usr/bin/zipinfo", ["-1", archive.path]).split(separator: "\n")
        guard !paths.isEmpty, paths.count < 10_000, paths.allSatisfy({ path in
            path.hasPrefix("PadDisplay.app/") && path.count < 1024 && !path.contains("\\") &&
            !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        }) else { throw failure("安装包目录结构无效。") }
        let listing = try run("/usr/bin/zipinfo", ["-l", archive.path])
        guard !listing.split(separator: "\n").contains(where: { $0.first == "l" }) else {
            throw failure("安装包包含不支持的符号链接。")
        }
        let totals = try run("/usr/bin/zipinfo", ["-t", archive.path])
        let pattern = try NSRegularExpression(pattern: #"([0-9]+) bytes uncompressed"#)
        guard let match = pattern.firstMatch(in: totals, range: NSRange(totals.startIndex..., in: totals)),
              let range = Range(match.range(at: 1), in: totals), let size = Int(totals[range]), size <= 536_870_912 else {
            throw failure("安装包解压大小超出允许范围。")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        return directory.appendingPathComponent("PadDisplay.app", isDirectory: true)
    }

    static func validate(_ candidate: URL, against current: URL, release: ReleaseManifest) throws {
        let plist = candidate.appendingPathComponent("Contents/Info.plist")
        guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "local.PadDisplay",
              info["CFBundleExecutable"] as? String == "PadDisplay",
              info["CFBundleShortVersionString"] as? String == release.version,
              String(describing: info["CFBundleVersion"] ?? "") == String(release.build),
              let minimum = info["LSMinimumSystemVersion"] as? String,
              !VersionNumber(minimum).parts.isEmpty,
              VersionNumber(minimum) <= systemVersion else { throw failure("应用身份、版本或系统要求与更新说明不一致。") }
        let architectures = try run("/usr/bin/lipo", ["-archs", candidate.appendingPathComponent("Contents/MacOS/PadDisplay").path]).split(whereSeparator: { $0.isWhitespace })
        #if arch(arm64)
        guard architectures.contains("arm64") else { throw failure("更新包不支持这台 Apple Silicon Mac。") }
        #else
        guard architectures.contains("x86_64") else { throw failure("更新包不支持这台 Intel Mac。") }
        #endif
        var installed: SecStaticCode?, downloaded: SecStaticCode?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(current as CFURL, [], &installed) == errSecSuccess, let installed,
              SecCodeCopyDesignatedRequirement(installed, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(candidate as CFURL, [], &downloaded) == errSecSuccess, let downloaded,
              SecStaticCodeCheckValidity(downloaded, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), requirement) == errSecSuccess else {
            throw failure("更新包未通过当前应用签名身份校验。请从项目发布页核实后手动安装。")
        }
    }

    static var systemVersion: VersionNumber {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return VersionNumber("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }

    static func prepare(_ candidate: URL, current: URL, release: ReleaseManifest) throws -> URL {
        let parent = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path),
              current.pathExtension == "app", !current.path.contains("/AppTranslocation/") else {
            throw failure("当前应用目录不可写。请从发布页下载，并拖入「应用程序」完成更新。")
        }
        let staged = parent.appendingPathComponent(".PadDisplay-update-\(UUID().uuidString).app")
        do {
            _ = try run("/usr/bin/ditto", [candidate.path, staged.path])
            try validate(staged, against: current, release: release)
            return staged
        } catch { try? FileManager.default.removeItem(at: staged); throw error }
    }

    static func replaceAfterQuit(staged: URL, current: URL) throws {
        let backup = current.deletingLastPathComponent().appendingPathComponent(".PadDisplay-backup-\(UUID().uuidString).app")
        let script = #"""
        for attempt in {1..300}; do
          kill -0 "$1" 2>/dev/null || break
          sleep 0.3
        done
        if kill -0 "$1" 2>/dev/null; then rm -rf "$3"; exit 1; fi
        if ! mv "$2" "$4"; then rm -rf "$3"; exit 1; fi
        if ! mv "$3" "$2"; then mv "$4" "$2"; /usr/bin/open "$2"; exit 1; fi
        if ! /usr/bin/open -n "$2"; then
          rm -rf "$2"
          mv "$4" "$2"
          /usr/bin/open "$2"
          exit 1
        fi
        rm -rf "$4"
        """#
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "PadDisplay-update", String(ProcessInfo.processInfo.processIdentifier), current.path, staged.path, backup.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure("安装包处理失败：\(executable.split(separator: "/").last ?? "工具")。") }
        return String(decoding: data, as: UTF8.self)
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "PadDisplay.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
