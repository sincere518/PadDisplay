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
        XCTAssertEqual(tracker.update([ipad], reportedCount: nil, now: t), [ipad])
        XCTAssertEqual(tracker.update([], reportedCount: nil, now: t.addingTimeInterval(1)), [ipad])
        XCTAssertEqual(tracker.update(["iPhone Air"], reportedCount: nil, now: t.addingTimeInterval(2)), ["iPhone Air"])
        XCTAssertEqual(tracker.update([], reportedCount: nil, now: t.addingTimeInterval(3)), ["iPhone Air"])
        XCTAssertEqual(tracker.update([], reportedCount: nil, now: t.addingTimeInterval(6)), [])
    }

    func testUnavailableAndDuplicateDeviceNames() {
        var tracker = ConnectionTracker()
        let t = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(tracker.update([ipad, ipad], reportedCount: nil, now: t), [ipad])
        XCTAssertEqual(tracker.update(nil, reportedCount: nil, now: t.addingTimeInterval(14)), [ipad])
        XCTAssertEqual(tracker.update(nil, reportedCount: nil, now: t.addingTimeInterval(15)), [])
    }

    func testProfilesDoNotFallbackToAnotherDevice() {
        let pad = DeviceProfile(name: ipad, spec: .init(width: 2732, height: 2048))
        let phone = DeviceProfile(name: "iPhone Air", spec: .init(width: 2736, height: 1260))
        let pc = DeviceProfile(name: "MacBook", enabled: false, spec: pad.spec)
        let profiles = [pad, phone, pc]
        XCTAssertEqual(DeviceDecision.resolve(names: [ipad], controllerCount: 1, profiles: profiles), .use(pad))
        XCTAssertEqual(DeviceDecision.resolve(names: [phone.name], controllerCount: 1, profiles: profiles), .use(phone))
        XCTAssertEqual(DeviceDecision.resolve(names: [pc.name], controllerCount: 1, profiles: profiles), .idle)
        XCTAssertEqual(DeviceDecision.resolve(names: ["陌生设备"], controllerCount: 1, profiles: profiles), .configure("陌生设备"))
        XCTAssertEqual(DeviceDecision.resolve(names: [ipad, phone.name], controllerCount: 2, profiles: profiles), .simultaneous)
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

    func testDisabledDeviceCanIgnoreInvalidHiddenSizeFields() {
        let profile = DeviceProfile(name: "MacBook", enabled: false, spec: .init(width: 2732, height: 2048))
        XCTAssertEqual(profile.applyingSizeInput(width: "abc", height: ""), profile)
    }

    func testEnabledDeviceRejectsNonNumericSizeInput() {
        let profile = DeviceProfile(name: ipad, spec: .init(width: 2732, height: 2048))
        XCTAssertNil(profile.applyingSizeInput(width: "abc", height: "2048"))
        XCTAssertEqual(profile.applyingSizeInput(width: "2048", height: "2732")?.spec,
                       DisplaySpec(width: 2048, height: 2732))
    }

    func testSameNamedControllersAreStillMultipleConnections() {
        let name = "iPhone Air"
        let count = UUControllerParser.controllerCount(in: ["本机被控中 当前有 2 台设备正在控制此电脑"])
        let profile = DeviceProfile(name: name, spec: .init(width: 2736, height: 1260))
        var tracker = ConnectionTracker()
        tracker.update([name, name], reportedCount: count, now: Date())
        XCTAssertEqual(DeviceDecision.resolve(names: tracker.names, controllerCount: tracker.controllerCount,
                                              profiles: [profile]), .simultaneous)
    }

    func testConnectionCountHeadersAndDuplicateAXLabels() {
        XCTAssertEqual(UUControllerParser.controllerCount(in: ["本机被控中 当前有 0 台设备正在控制此电脑"]), 0)
        XCTAssertEqual(UUControllerParser.controllerCount(in: ["当前有 1 台设备正在控制此电脑", "当前有 1 台设备正在控制此电脑"]), 1)
        XCTAssertNil(UUControllerParser.controllerCount(in: ["本机被控中", "连接时长 00:02:04"]))
    }

    func testKnownMultipleConnectionsPauseWhenNamesAreUnavailable() {
        var tracker = ConnectionTracker()
        let t = Date(timeIntervalSince1970: 100)
        let profile = DeviceProfile(name: ipad, spec: .init(width: 2732, height: 2048))
        tracker.update([ipad], reportedCount: 1, now: t)
        tracker.update(nil, reportedCount: 2, now: t.addingTimeInterval(1))
        tracker.update(nil, reportedCount: nil, now: t.addingTimeInterval(2))
        XCTAssertEqual(DeviceDecision.resolve(names: tracker.names, controllerCount: tracker.controllerCount,
                                              profiles: [profile]), .simultaneous)
        tracker.update(nil, reportedCount: 1, now: t.addingTimeInterval(3))
        XCTAssertEqual(DeviceDecision.resolve(names: tracker.names, controllerCount: tracker.controllerCount,
                                              profiles: [profile]), .idle, "连接数变化且名称未知时不能沿用旧设备配置")
        tracker.update(nil, reportedCount: 2, now: t.addingTimeInterval(16))
        XCTAssertTrue(tracker.names.isEmpty, "不能无限保留旧设备名称")
        XCTAssertEqual(DeviceDecision.resolve(names: tracker.names, controllerCount: tracker.controllerCount,
                                              profiles: [profile]), .simultaneous)
        tracker.update([ipad], reportedCount: 1, now: t.addingTimeInterval(17))
        XCTAssertEqual(DeviceDecision.resolve(names: tracker.names, controllerCount: tracker.controllerCount,
                                              profiles: [profile]), .use(profile))
        tracker.update([], reportedCount: 0, now: t.addingTimeInterval(18))
        tracker.update([], reportedCount: 0, now: t.addingTimeInterval(21))
        XCTAssertEqual(tracker.controllerCount, 0)
    }

    func testAddingUnknownDeviceDoesNotActivateUnconfirmedDimensions() {
        let name = "我的手机"
        let draft = DeviceProfile.draft(for: name)
        XCTAssertFalse(draft.enabled)
        XCTAssertNotNil(draft.spec.validationError, "未知设备需要确认尺寸，不能沿用 iPad 默认值")
        XCTAssertEqual(DeviceDecision.resolve(names: [name], controllerCount: 1, profiles: [draft]), .idle)
        var saved = draft
        saved.enabled = true
        saved.spec = DisplaySpec(width: 2868, height: 1320)
        XCTAssertEqual(DeviceDecision.resolve(names: [name], controllerCount: 1, profiles: [saved]), .use(saved))
    }
}
