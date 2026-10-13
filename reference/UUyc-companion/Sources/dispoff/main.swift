// P0 探测：远程期间禁用物理屏（CGSConfigureDisplayEnabled 私有 API）
// 用法：
//   dispoff probe [秒数=8] [app|session]   建虚拟屏+禁用物理屏，停留后【不恢复】直接退出，验证 forAppOnly 自动撤销
//   dispoff restore                          兜底：重新启用所有已连接但被禁用的显示器
//   dispoff list                             列出在线/活动显示器
import CGVirtualDisplayBridge
import CoreGraphics
import Foundation

typealias EnableFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSConfigureDisplayEnabled") else {
    print("❌ 本系统没有 CGSConfigureDisplayEnabled"); exit(1)
}
let setEnabled = unsafeBitCast(sym, to: EnableFn.self)
setvbuf(stdout, nil, _IOLBF, 0)

func list(_ f: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError) -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    _ = f(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    _ = f(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}
func online() -> [CGDirectDisplayID] { list(CGGetOnlineDisplayList) }
func active() -> [CGDirectDisplayID] { list(CGGetActiveDisplayList) }
func dump(_ t: String) {
    let a = Set(active())
    print("== \(t)")
    for id in online() {
        let b = CGDisplayBounds(id)
        print("  #\(id) \(a.contains(id) ? "启用" : "禁用") \(Int(b.width))x\(Int(b.height))@\(Int(b.origin.x)),\(Int(b.origin.y))\(CGDisplayIsMain(id) != 0 ? " [主屏]" : "")\(CGDisplayIsBuiltin(id) != 0 ? " 内建" : "")")
    }
}
func configure(_ opt: CGConfigureOption, _ body: (CGDisplayConfigRef?) -> Void) -> CGError {
    var cfg: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&cfg)
    body(cfg)
    let e = CGCompleteDisplayConfiguration(cfg, opt)
    if e != .success { CGCancelDisplayConfiguration(cfg) }
    return e
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "list" {
case "restore":
    dump("恢复前")
    let off = online().filter { !active().contains($0) }
    let e = configure(.forSession) { c in off.forEach { _ = setEnabled(c, $0, true) } }
    print("重新启用 \(off) → CGError=\(e.rawValue)")
    Thread.sleep(forTimeInterval: 2)
    dump("恢复后")
case "probe":
    let hold = args.count > 2 ? Double(args[2]) ?? 8 : 8
    let opt: CGConfigureOption = (args.count > 3 && args[3] == "session") ? .forSession : .forAppOnly
    let physical = online()
    let desc = CGVirtualDisplayDescriptor()
    desc.name = "UUDisplay DispOff Probe"
    desc.maxPixelsWide = 2360; desc.maxPixelsHigh = 1640
    desc.sizeInMillimeters = CGSize(width: 272, height: 189)
    desc.vendorID = 0x5555; desc.productID = 0x0002; desc.serialNum = UInt32.random(in: 1...0xFFFF_FFF0)
    let vd: CGVirtualDisplay? = autoreleasepool { CGVirtualDisplay(descriptor: desc) }
    guard let vd else { print("❌ 建虚拟屏失败"); exit(2) }
    let s = CGVirtualDisplaySettings(); s.hiDPI = true
    s.modes = [CGVirtualDisplayMode(width: 1180, height: 820, refreshRate: 60)]
    guard vd.apply(s) else { print("❌ apply 失败"); exit(2) }
    for _ in 0..<20 where !online().contains(vd.displayID) { Thread.sleep(forTimeInterval: 0.25) }
    dump("建虚拟屏后")
    let e = configure(opt) { c in
        CGConfigureDisplayOrigin(c, vd.displayID, 0, 0)
        physical.forEach { _ = setEnabled(c, $0, false) }
    }
    print("禁用物理屏（\(opt == .forAppOnly ? "forAppOnly" : "forSession")）→ CGError=\(e.rawValue)")
    Thread.sleep(forTimeInterval: 1.5)
    dump("禁用后")
    Thread.sleep(forTimeInterval: hold)
    print("不做恢复，直接退出")
    exit(0)
default:
    dump("当前")
}
