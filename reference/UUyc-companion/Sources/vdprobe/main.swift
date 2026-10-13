// P0 探测：在本机创建 HiDPI 虚拟屏 → 设为主屏 → 还原 → 释放，并打印每一步的显示器状态。
// 用法：vdprobe <像素宽> <像素高> [停留秒数=8] [--no-main]
import CGVirtualDisplayBridge
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let pixelW = args.count > 1 ? Int(args[1]) ?? 2360 : 2360
let pixelH = args.count > 2 ? Int(args[2]) ?? 1640 : 1640
let hold = args.count > 3 ? Double(args[3]) ?? 8 : 8
let setMain = !args.contains("--no-main")

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func describe(_ id: CGDirectDisplayID) -> String {
    let b = CGDisplayBounds(id)
    let mode = CGDisplayCopyDisplayMode(id)
    let px = mode.map { "\($0.pixelWidth)x\($0.pixelHeight)px" } ?? "?"
    let pt = mode.map { "\($0.width)x\($0.height)pt" } ?? "?"
    let main = CGDisplayIsMain(id) != 0 ? " [主屏]" : ""
    return "  #\(id) 原点(\(Int(b.origin.x)),\(Int(b.origin.y))) \(pt) \(px)\(main)"
}

func dump(_ title: String) {
    print("== \(title)")
    onlineDisplays().forEach { print(describe($0)) }
}

/// 把 target 移到 (0,0) 成为主屏，其余显示器整体平移保持相对布局
func makeMain(_ target: CGDirectDisplayID) -> CGError {
    let t = CGDisplayBounds(target).origin
    var cfg: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&cfg)
    for id in onlineDisplays() {
        let o = CGDisplayBounds(id).origin
        CGConfigureDisplayOrigin(cfg, id, Int32(o.x - t.x), Int32(o.y - t.y))
    }
    return CGCompleteDisplayConfiguration(cfg, .forSession)
}


if args.contains("--list") { dump("当前显示器"); exit(0) }

/// UU 被控时 UURemoteServer 会在各屏铺覆盖窗口，以此判断是否有设备连入（无需权限）
func uuControlled() -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.contains { ($0[kCGWindowOwnerName as String] as? String) == "UURemoteServer" }
}
let waitUU = args.contains("--wait-uu")
if waitUU {
    print("…等待 UU 连入")
    while !uuControlled() { Thread.sleep(forTimeInterval: 0.5) }
    print("✅ 检测到 UU 连入")
}

let desc = CGVirtualDisplayDescriptor()
desc.name = "UUDisplay Probe"
desc.maxPixelsWide = UInt32(pixelW)
desc.maxPixelsHigh = UInt32(pixelH)
desc.sizeInMillimeters = CGSize(width: Double(pixelW) / 220 * 25.4, height: Double(pixelH) / 220 * 25.4)
desc.vendorID = 0x5555
desc.productID = 0x0001
desc.serialNum = 0x0001

var vd: CGVirtualDisplay! = autoreleasepool { CGVirtualDisplay(descriptor: desc) }
if vd == nil {
    print("❌ CGVirtualDisplay(descriptor:) 返回 nil —— 私有 API 在本系统不可用")
    exit(1)
}
print("✅ 虚拟屏对象已创建，displayID=\(vd.displayID)")

// 只给一个 HiDPI 模式：逻辑尺寸 = 像素 / 2，创建后不再改模式
let settings = CGVirtualDisplaySettings()
settings.hiDPI = true
settings.modes = [CGVirtualDisplayMode(width: UInt(pixelW / 2), height: UInt(pixelH / 2), refreshRate: 60)]
guard autoreleasepool(invoking: { vd.apply(settings) }) else {
    print("❌ applySettings 失败")
    exit(2)
}
print("✅ applySettings 成功")

RunLoop.main.run(until: Date().addingTimeInterval(2))
dump("创建后")
let originalMain = CGMainDisplayID()
let savedOrigins = onlineDisplays().filter { $0 != vd.displayID }.map { ($0, CGDisplayBounds($0).origin) }

if setMain {
    let err = makeMain(vd.displayID)
    print(err == .success ? "✅ 已设为主屏" : "❌ 设主屏失败 CGError=\(err.rawValue)")
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    dump("设为主屏后")
}

print("…停留 \(Int(hold)) 秒\(waitUU ? "（UU 断开则提前结束）" : "")")
let deadline = Date().addingTimeInterval(hold)
while Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    if waitUU && !uuControlled() {
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))  // 防抖：切屏时覆盖窗口会短暂重建
        if !uuControlled() { print("✅ 检测到 UU 断开"); break }
    }
}

if setMain {
    var cfg: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&cfg)
    for (id, o) in savedOrigins { CGConfigureDisplayOrigin(cfg, id, Int32(o.x), Int32(o.y)) }
    let err = CGCompleteDisplayConfiguration(cfg, .forSession)
    print(err == .success ? "✅ 已还原原布局" : "⚠️ 还原布局 CGError=\(err.rawValue)")
}

let vid = vd.displayID
autoreleasepool { vd = nil }  // 释放对象即移除虚拟屏
for _ in 0..<20 where onlineDisplays().contains(vid) {
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
}
dump("释放后")
let gone = !onlineDisplays().contains(vid)
let mainOK = CGMainDisplayID() == originalMain
print(gone ? "✅ 虚拟屏已消失" : "❌ 虚拟屏残留")
print(mainOK ? "✅ 主屏已恢复" : "⚠️ 主屏未恢复为 #\(originalMain)")
if let s = ProcessInfo.processInfo.environment["POST_HOLD"], let t = Double(s) { print("…释放后再停 \(Int(t)) 秒"); RunLoop.main.run(until: Date().addingTimeInterval(t)) }
