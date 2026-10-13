// 简易日志：同时输出到 stdout 和 ~/Library/Logs/UUDisplay.log
import Foundation

enum Log {
    private static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/UUDisplay.log")
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ msg: String) {
        let line = "[\(fmt.string(from: Date()))] \(msg)\n"
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
