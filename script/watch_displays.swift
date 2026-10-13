// 只读记录真实显示器变化，供客户端连接 / 断开测试使用。
// 长驻进程可能读不到新屏的显示模式；此时尺寸 0 表示不可读取，最终像素另用 system_profiler 核验。
import CoreGraphics
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let seconds = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 600 : 600
FileManager.default.createFile(atPath: destination.path, contents: nil)
let output = try FileHandle(forWritingTo: destination)
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let deadline = Date().addingTimeInterval(seconds)
var lastState = Data()

while Date() < deadline {
    var count: UInt32 = 0
    var screens: [[String: Any]] = []
    if CGGetOnlineDisplayList(0, nil, &count) == .success {
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        if CGGetOnlineDisplayList(count, &ids, &count) == .success {
            screens = ids.prefix(Int(count)).sorted().map { id in
                let mode = CGDisplayCopyDisplayMode(id)
                let origin = CGDisplayBounds(id).origin
                return ["id": id, "vendor": CGDisplayVendorNumber(id), "model": CGDisplayModelNumber(id),
                        "serial": CGDisplaySerialNumber(id), "main": CGDisplayIsMain(id) != 0,
                        "modeAvailable": mode != nil,
                        "pixelWidth": mode?.pixelWidth ?? 0, "pixelHeight": mode?.pixelHeight ?? 0,
                        "logicalWidth": mode?.width ?? 0, "logicalHeight": mode?.height ?? 0,
                        "refreshRate": mode?.refreshRate ?? 0, "x": Int(origin.x), "y": Int(origin.y)]
            }
        }
    }
    let state = try JSONSerialization.data(withJSONObject: screens, options: .sortedKeys)
    let value: [String: Any] = ["timestamp": formatter.string(from: Date()), "screens": screens]
    let line = try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
    output.write(line)
    output.write(Data([10]))
    if state != lastState {
        print(String(data: line, encoding: .utf8)!)
        fflush(stdout)
        lastState = state
    }
    Thread.sleep(forTimeInterval: 0.5)
}
try output.close()
