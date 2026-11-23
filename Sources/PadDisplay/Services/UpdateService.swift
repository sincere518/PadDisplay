import AppKit
import CryptoKit
import Observation
import PadDisplayCore

private final class BoundedUpdateTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // All mutable transfer state is used on URLSession's serial delegate queue.
    private let continuation: CheckedContinuation<Data, Error>
    private let file: FileHandle?
    private let limit: Int
    private let sizeError: String
    private var failure: Error?
    private var received = 0
    private var data = Data()

    private init(file: FileHandle?, limit: Int, sizeError: String, continuation: CheckedContinuation<Data, Error>) {
        self.file = file
        self.limit = limit
        self.sizeError = sizeError
        self.continuation = continuation
    }

    static func receive(from url: URL, limit: Int, sizeError: String, into destination: URL? = nil) async throws -> Data {
        let file: FileHandle?
        if let destination {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw UpdateInstaller.failure("无法创建更新下载文件。")
            }
            file = try FileHandle(forWritingTo: destination)
        } else { file = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = BoundedUpdateTransfer(file: file, limit: limit, sizeError: sizeError, continuation: continuation)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 180
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            session.dataTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(ReleaseManifest.secureURL) == true ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let response = response as? HTTPURLResponse else { throw UpdateInstaller.failure("更新服务器响应无效。") }
            guard response.statusCode == 200, response.url.map(ReleaseManifest.secureURL) == true else {
                if response.statusCode == 404 { throw UpdateInstaller.failure("发布页尚无更新描述文件，请稍后重试或查看发布页。") }
                if response.statusCode == 403 || response.statusCode == 429 {
                    throw UpdateInstaller.failure("发布服务暂时限制访问，请稍后重试。")
                }
                throw UpdateInstaller.failure("更新请求失败（HTTP \(response.statusCode)）。")
            }
            guard response.expectedContentLength <= Int64(limit) else { throw UpdateInstaller.failure(sizeError) }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard failure == nil else { return }
        do {
            guard chunk.count <= limit - received else { throw UpdateInstaller.failure(sizeError) }
            if let file { try file.write(contentsOf: chunk) }
            else { data.append(chunk) }
            received += chunk.count
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        do {
            try file?.close()
            if let error = failure ?? error { throw error }
            guard received > 0 else { throw UpdateInstaller.failure("更新服务器返回了空文件。") }
            continuation.resume(returning: data)
        } catch { continuation.resume(throwing: error) }
    }
}

@MainActor @Observable final class UpdateService {
    static let repository = "https://github.com/sincere518/PadDisplay"
    var source: String { didSet { UserDefaults.standard.set(source, forKey: "updateSource"); release = nil; cleanTemporary() } }
    var automaticChecks: Bool { didSet { UserDefaults.standard.set(automaticChecks, forKey: "updateChecks"); scheduleChecks() } }
    private(set) var busy = false
    private(set) var message = "点击检查以获取新版本。"
    private(set) var release: ReleaseManifest?
    private(set) var candidate: URL?
    private var temporary: URL?
    private var timer: Timer?
    private let current = Bundle.main.bundleURL

    init() {
        source = UserDefaults.standard.string(forKey: "updateSource") ?? Self.repository
        automaticChecks = UserDefaults.standard.bool(forKey: "updateChecks")
    }

    func checkIfScheduled() {
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        if automaticChecks, Date().timeIntervalSince(last) >= 86_400 { check() }
    }

    func scheduleChecks() {
        timer?.invalidate(); timer = nil
        guard automaticChecks else { return }
        checkIfScheduled()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfScheduled() }
        }
    }

    func stopChecks() { timer?.invalidate(); timer = nil }

    func check() {
        guard !busy else { return }
        busy = true; release = nil; candidate = nil; message = "正在检查更新…"
        Task {
            defer { busy = false }
            do {
                guard var url = URL(string: source.trimmingCharacters(in: .whitespacesAndNewlines)), ReleaseManifest.secureURL(url) else {
                    throw UpdateInstaller.failure("请输入 HTTPS 发布仓库或更新描述文件地址。")
                }
                if url.host == "github.com", url.path.split(separator: "/").count == 2 {
                    url.appendPathComponent("releases/latest/download/PadDisplay-update.json")
                }
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                let data = try await BoundedUpdateTransfer.receive(from: url, limit: 1_048_576, sizeError: "更新描述文件过大。")
                let manifest = try JSONDecoder().decode(ReleaseManifest.self, from: data); try manifest.validate()
                guard VersionNumber(manifest.minimumSystemVersion) <= UpdateInstaller.systemVersion else {
                    throw UpdateInstaller.failure("新版本要求 macOS \(manifest.minimumSystemVersion) 或更高版本。")
                }
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
                if manifest.isNewer(than: version, build: build) { release = manifest; message = "发现新版本 \(manifest.version)。" }
                else { message = "当前已是最新版本（\(version)）。" }
            } catch { message = error.localizedDescription }
        }
    }

    func download() {
        guard !busy, let release else { return }
        busy = true; message = "正在下载并校验更新…"
        Task {
            defer { busy = false }
            do {
                if let temporary { try? FileManager.default.removeItem(at: temporary) }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PadDisplay-update-\(UUID().uuidString)", isDirectory: true)
                temporary = directory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let archive = directory.appendingPathComponent("PadDisplay.zip")
                _ = try await BoundedUpdateTransfer.receive(from: release.downloadURL, limit: 268_435_456,
                                                           sizeError: "更新包大小超出允许范围。", into: archive)
                let installed = current
                candidate = try await Task.detached {
                    let hash = SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
                    guard hash == release.sha256.lowercased() else { throw UpdateInstaller.failure("安装包 SHA-256 不匹配，已停止更新。") }
                    let app = try UpdateInstaller.unpack(archive, into: directory.appendingPathComponent("unpacked"))
                    try UpdateInstaller.validate(app, against: installed, release: release)
                    return app
                }.value
                message = "已通过文件与签名身份校验，可以安装 \(release.version)。"
            } catch { candidate = nil; message = error.localizedDescription; cleanTemporary() }
        }
    }

    func install(model: AppController) {
        guard !busy, !model.report.busy, let candidate, let release else { return }
        busy = true; message = "正在准备更新…"
        let current = current.resolvingSymlinksInPath()
        Task { [self] in
            do {
                let staged = try await Task.detached { try UpdateInstaller.prepare(candidate, current: current, release: release) }.value
                message = "正在恢复桌面，随后更新并重新打开…"
                model.shutdown { [weak self] in
                    guard let self else { return }
                    do {
                        guard !model.report.failed, !model.report.recoveryNeeded else { throw UpdateInstaller.failure("桌面尚未恢复，更新已停止。请先处理恢复错误。") }
                        try UpdateInstaller.replaceAfterQuit(staged: staged, current: current, release: release)
                        self.cleanTemporary(); NSApp.terminate(nil)
                    } catch {
                        try? FileManager.default.removeItem(at: staged)
                        self.busy = false; self.message = error.localizedDescription; model.start()
                    }
                }
            } catch { busy = false; message = error.localizedDescription }
        }
    }

    func openReleases() { NSWorkspace.shared.open(URL(string: Self.repository + "/releases")!) }
    func cleanTemporary() { if let temporary { try? FileManager.default.removeItem(at: temporary) }; temporary = nil; candidate = nil }
    func noteRollback() { message = "更新未完成，已重新打开原版本。" }
}
