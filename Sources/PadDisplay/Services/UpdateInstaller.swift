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

    private struct ExpectedStartup: Codable {
        let path: String
        let version: String
        let build: String
    }

    private static func startupDirectory(for token: UUID) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PadDisplay-startup-\(token.uuidString)", isDirectory: true)
    }

    static func acknowledgeStartup() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--update-startup-ack"), args.indices.contains(index + 1),
              let token = UUID(uuidString: args[index + 1]) else { return }
        let directory = startupDirectory(for: token)
        let bundle = Bundle.main
        do {
            let metadata = try Data(contentsOf: directory.appendingPathComponent("expected.json"))
            let expected = try JSONDecoder().decode(ExpectedStartup.self, from: metadata)
            guard bundle.bundleURL.resolvingSymlinksInPath().path == expected.path,
                  bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expected.version,
                  String(describing: bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "") == expected.build else { return }
            try String(ProcessInfo.processInfo.processIdentifier).write(to: directory.appendingPathComponent("ready"),
                                                                       atomically: true, encoding: .utf8)
        } catch {
            NSLog("PadDisplay could not acknowledge the updated application: %@", error.localizedDescription)
        }
    }

    static func replaceAfterQuit(staged: URL, current: URL, release: ReleaseManifest) throws {
        let backup = current.deletingLastPathComponent().appendingPathComponent(".PadDisplay-backup-\(UUID().uuidString).app")
        let token = UUID()
        let acknowledgement = startupDirectory(for: token)
        try FileManager.default.createDirectory(at: acknowledgement, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let script = #"""
        trap 'rm -rf "$5"' EXIT
        executable="$2/Contents/MacOS/PadDisplay"

        matching_process() {
          [[ "$1" =~ ^[1-9][0-9]*$ ]] && [[ "$(/bin/ps -ww -p "$1" -o comm= 2>/dev/null)" == "$executable" ]]
        }

        new_application_running() {
          local pids status pid path
          pids=$(/usr/bin/pgrep -x PadDisplay) || { status=$?; [[ "$status" == 1 ]] && return 1; return 2; }
          for pid in $pids; do
            if path=$(/bin/ps -ww -p "$pid" -o comm= 2>/dev/null); then
              [[ "$path" != "$executable" ]] || return 0
            elif kill -0 "$pid" 2>/dev/null; then
              return 2
            fi
          done
          return 1
        }

        restore_original() {
          if [[ ! -e "$2" && ! -L "$2" ]] && mv "$4" "$2"; then
            rm -rf "$3"
            /usr/bin/open -n "$2" --args --update-rollback
          else
            /usr/bin/logger -t PadDisplay "Could not restore the old application. Backup retained at $4."
          fi
        }

        for attempt in {1..300}; do
          kill -0 "$1" 2>/dev/null || break
          sleep 0.3
        done
        if kill -0 "$1" 2>/dev/null; then rm -rf "$3"; exit 1; fi
        if ! mv "$2" "$4"; then
          rm -rf "$3"
          /usr/bin/open -n "$2" --args --update-rollback
          exit 1
        fi
        if ! mv "$3" "$2"; then
          restore_original "$@"
          exit 1
        fi
        if /usr/bin/open -n "$2" --args --update-startup-ack "$6"; then
          for attempt in {1..60}; do
            if [[ -f "$5/ready" ]]; then
              pid=$(cat "$5/ready")
              if matching_process "$pid"; then
                sleep 2
                if matching_process "$pid"; then rm -rf "$4"; exit 0; fi
              fi
            fi
            sleep 0.25
          done
        fi
        new_application_running
        if [[ "$?" == 1 ]] && mv "$2" "$3"; then
          restore_original "$@"
        else
          /usr/bin/logger -t PadDisplay "Updated application did not confirm readiness. Backup retained at $4."
        fi
        exit 1
        """#
        do {
            let expected = ExpectedStartup(path: current.path, version: release.version, build: String(release.build))
            try JSONEncoder().encode(expected).write(to: acknowledgement.appendingPathComponent("expected.json"), options: .atomic)
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script, "PadDisplay-update", String(ProcessInfo.processInfo.processIdentifier),
                                 current.path, staged.path, backup.path, acknowledgement.path, token.uuidString]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: acknowledgement)
            throw error
        }
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
