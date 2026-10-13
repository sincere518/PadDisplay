import Foundation

@main struct ControllerReaderTests {
    static func main() {
        let ipad = "iPad Air (13 英寸, M2)"
        let cases: [([String], String?)] = [
            (["\(ipad) 远程控制 连接时长 00:02:04"], ipad),
            ([ipad, "远程控制", "连接时长 00:02:04"], ipad),
            ([ipad, "远程控制 连接时长 00:02:04"], ipad),
            (["  \(ipad)   远程控制  连接时长  00:02:04  "], ipad),
            (["耳过清风的iMac", "远程控制", "连接时长 12:00:00"], "耳过清风的iMac"),
            ([], nil),
            (["本机被控中 当前有 0 台设备正在控制此电脑"], nil),
            (["远程控制"], nil),
            (["我的远程控制设备"], nil),
            (["我的设备 远程控制"], nil),
            ([ipad, "观看模式", "连接时长 00:02:04"], nil),
        ]
        var failures = 0
        for (texts, expected) in cases {
            let actual = UUReader.controllerName(in: texts)
            if actual != expected {
                print("FAIL: \(texts) -> \(String(describing: actual)), expected \(String(describing: expected))")
                failures += 1
            }
        }
        guard failures == 0 else { exit(1) }
        print("PASS: \(cases.count) controller row cases, including the observed UU 4.42.0 iPad session")
    }
}
