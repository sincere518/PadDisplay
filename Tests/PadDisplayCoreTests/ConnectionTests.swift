import XCTest
@testable import PadDisplayCore

final class ConnectionTests: XCTestCase {
    let ipad = "iPad Air (13 英寸, M2)"

    func testObservedUURemote442Row() {
        XCTAssertEqual(UUControllerParser.name(in: ["\(ipad) 远程控制 连接时长 00:02:04"]), ipad)
        XCTAssertEqual(UUControllerParser.name(in: [ipad, "远程控制 连接时长 00:02:04"]), ipad)
        XCTAssertEqual(UUControllerParser.name(in: ["  \(ipad)   远程控制  连接时长  00:02:04  "]), ipad)
    }

    func testSeparateFieldsAndFalsePositives() {
        XCTAssertEqual(UUControllerParser.name(in: [ipad, "远程控制", "连接时长 00:02:04"]), ipad)
        for fields in [[], ["远程控制"], ["我的设备 远程控制"], ["我的远程控制设备"],
                       [ipad, "观看模式", "连接时长 00:02:04"], ["当前有 0 台设备正在控制此电脑"]] {
            XCTAssertNil(UUControllerParser.name(in: fields))
        }
    }

    func testSwitchDeviceAndDebouncedDisconnect() {
        var tracker = ConnectionTracker()
        let t = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(tracker.update([ipad], now: t), [ipad])
        XCTAssertEqual(tracker.update([], now: t.addingTimeInterval(1)), [ipad])
        XCTAssertEqual(tracker.update(["iPhone Air"], now: t.addingTimeInterval(2)), ["iPhone Air"])
        XCTAssertEqual(tracker.update([], now: t.addingTimeInterval(3)), ["iPhone Air"])
        XCTAssertEqual(tracker.update([], now: t.addingTimeInterval(6)), [])
    }

    func testUnavailableAndDuplicateDeviceNames() {
        var tracker = ConnectionTracker()
        let t = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(tracker.update([ipad, ipad], now: t), [ipad])
        XCTAssertEqual(tracker.update(nil, now: t.addingTimeInterval(14)), [ipad])
        XCTAssertEqual(tracker.update(nil, now: t.addingTimeInterval(15)), [])
    }

    func testProfilesDoNotFallbackToAnotherDevice() {
        let pad = DeviceProfile(name: ipad, spec: .init(width: 2732, height: 2048))
        let phone = DeviceProfile(name: "iPhone Air", spec: .init(width: 2736, height: 1260))
        let pc = DeviceProfile(name: "MacBook", enabled: false, spec: pad.spec)
        let profiles = [pad, phone, pc]
        XCTAssertEqual(DeviceDecision.resolve(names: [ipad], profiles: profiles), .use(pad))
        XCTAssertEqual(DeviceDecision.resolve(names: [phone.name], profiles: profiles), .use(phone))
        XCTAssertEqual(DeviceDecision.resolve(names: [pc.name], profiles: profiles), .idle)
        XCTAssertEqual(DeviceDecision.resolve(names: ["陌生设备"], profiles: profiles), .configure("陌生设备"))
        XCTAssertEqual(DeviceDecision.resolve(names: [ipad, phone.name], profiles: profiles), .simultaneous)
    }

    func testUnambiguousModelPresetsAndDimensions() {
        XCTAssertEqual(ScreenPreset.suggested(for: ipad)?.spec.width, 2732)
        XCTAssertEqual(ScreenPreset.suggested(for: "iPhone Air")?.spec.width, 2736)
        XCTAssertEqual(ScreenPreset.suggested(for: "iPhone 17 Pro Max")?.spec.height, 1320)
        XCTAssertNil(ScreenPreset.suggested(for: "iPad Air"))
        XCTAssertNil(ScreenPreset.suggested(for: "iPad Air 11 英寸 / 13 英寸"))
        XCTAssertNil(ScreenPreset.suggested(for: "iPad Pro 13 英寸 (M2)"))
        XCTAssertNil(ScreenPreset.suggested(for: "我的平板"))
        XCTAssertNil(DisplaySpec(width: 2732, height: 2048).validationError)
        XCTAssertNotNil(DisplaySpec(width: 639, height: 2048).validationError)
        XCTAssertNotNil(DisplaySpec(width: 9000, height: 2048).validationError)
        XCTAssertNotNil(DisplaySpec(width: 2731, height: 2048).validationError)
    }
}
