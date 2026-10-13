import XCTest
import PadDisplayCore
@testable import PadDisplay

final class UIStateTests: XCTestCase {
    func testNewDraftDoesNotChangeProfilesPreferencesOrActiveDisplay() async {
        await MainActor.run {
            withModel("ready") { model, preferences in
                let profiles = model.profiles
                let active = model.report.active
                let stored = preferences.data(forKey: "profiles")
                var draft = model.makeDraft()
                draft.name = "我的手机"
                draft.spec = .init(width: 2868, height: 1320)
                XCTAssertEqual(model.profiles, profiles)
                XCTAssertEqual(model.report.active, active)
                XCTAssertEqual(preferences.data(forKey: "profiles"), stored)
            }
        }
    }

    func testInvalidNamesDimensionsAndDuplicatesDoNotPersist() async {
        await MainActor.run {
            withModel("ready") { model, preferences in
                let original = model.profiles
                let active = model.report.active
                for profile in [DeviceProfile(name: " ", spec: .init(width: 2732, height: 2048)),
                                DeviceProfile(name: original[0].name, spec: original[0].spec),
                                DeviceProfile(name: "新手机", spec: .init(width: 639, height: 1320)),
                                DeviceProfile(name: "新手机", spec: .init(width: 2731, height: 2048))] {
                    XCTAssertFalse(model.save(profile))
                    XCTAssertEqual(model.profiles, original)
                    XCTAssertEqual(model.report.active, active)
                }
                XCTAssertNil(preferences.data(forKey: "profiles"))
            }
        }
    }

    func testSavingValidPortraitConfigurationUpdatesOnlyThatDevice() async {
        await MainActor.run {
            withModel("ready") { model, preferences in
                let phone = model.profiles[1]
                var pad = model.profiles[0]
                pad.spec = .init(width: 2048, height: 2732)
                XCTAssertTrue(model.save(pad))
                XCTAssertEqual(model.profiles[1], phone)
                XCTAssertEqual(model.report.active?.spec, pad.spec)
                XCTAssertEqual(model.sessionState, .ready)
                let saved = try? JSONDecoder().decode([DeviceProfile].self, from: preferences.data(forKey: "profiles")!)
                XCTAssertEqual(saved?.first, pad)
            }
        }
    }

    func testRestorePauseManualAndAutomaticStates() async {
        await MainActor.run {
            withModel("ready") { model, _ in
                model.restore()
                XCTAssertEqual(model.sessionState, .paused)
                XCTAssertTrue(model.automatic)
                XCTAssertNil(model.report.active)
                model.resumeAutomatic()
                XCTAssertEqual(model.sessionState, .ready)
                model.automatic = false
                XCTAssertEqual(model.sessionState, .disabled)
                model.useManually(model.profiles[1])
                XCTAssertEqual(model.sessionState, .manual)
                XCTAssertEqual(model.report.active?.name, "iPhone 17 Pro Max")
                model.resumeAutomatic()
                XCTAssertEqual(model.report.active?.name, model.profiles[0].name)
            }
        }
    }

    func testUnconfirmedConnectionsAndFailuresAreNotPresentedAsReady() async {
        await MainActor.run {
            for (scenario, expected) in [("permission", SessionState.permission), ("multiple", .multiple),
                                         ("unknown", .unconfigured), ("busy", .working), ("failed", .recoveryFailed),
                                         ("idle", .waiting), ("phone", .ready)] {
                withModel(scenario) { model, _ in
                    XCTAssertEqual(model.sessionState, expected, scenario)
                    if scenario == "multiple" { model.resumeAutomatic(); XCTAssertNil(model.report.active) }
                    if scenario == "unknown" {
                        let draft = model.makeDraft()
                        XCTAssertEqual(draft.name, "我的手机")
                        XCTAssertFalse(draft.enabled)
                        XCTAssertNotNil(draft.spec.validationError)
                    }
                }
            }
        }
    }

    @MainActor private func withModel(_ scenario: String, body: (AppController, UserDefaults) -> Void) {
        let domain = "PadDisplay-test-\(UUID())"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = AppController(preferences: preferences, validationScenario: scenario)
        model.start()
        body(model, preferences)
        model.shutdown({})
    }
}
