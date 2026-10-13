import XCTest
@testable import PadDisplay

final class RecoveryTests: XCTestCase {
    func testDisplayReadFailurePreservesRecoveryRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PadDisplay-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("display-session.json")
        let original = Data(#"[{"id":42,"vendor":1,"model":2,"serial":3,"x":0,"y":0}]"#.utf8)
        try original.write(to: journal)
        let service = VirtualDisplayService(supportDirectory: directory, readDisplays: {
            throw NSError(domain: "TestDisplayEnumeration", code: 1)
        })
        let finished = expectation(description: "Recovery reports display enumeration failure")
        service.onChange = { report in
            XCTAssertTrue(report.failed, "读取显示器失败不能视为全部已断开")
            finished.fulfill()
        }
        service.recover()
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(try Data(contentsOf: journal), original)
    }

    func testRetryDoesNotClaimCorruptJournalWasRestored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PadDisplay-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("display-session.json")
        let original = Data("not valid JSON".utf8)
        try original.write(to: journal)
        let service = VirtualDisplayService(supportDirectory: directory)
        let initialFailure = expectation(description: "Initial recovery reports corruption")
        service.onChange = { report in
            if report.failed { initialFailure.fulfill() }
        }
        service.recover()
        wait(for: [initialFailure], timeout: 3)

        let retryFinished = expectation(description: "Retry finishes without changing display topology")
        var retryFailed = false
        service.onChange = { report in
            if !report.busy {
                retryFailed = report.failed
                retryFinished.fulfill()
            }
        }
        service.request(nil, retry: true)
        wait(for: [retryFinished], timeout: 3)
        XCTAssertTrue(retryFailed, "损坏记录尚未恢复时不能显示成功")
        XCTAssertEqual(try Data(contentsOf: journal), original, "失败的恢复必须保留原记录")

        try Data("[]".utf8).write(to: journal)
        let repaired = expectation(description: "Repaired journal can be recovered on retry")
        service.onChange = { report in
            if !report.busy {
                XCTAssertFalse(report.failed)
                repaired.fulfill()
            }
        }
        service.request(nil, retry: true)
        wait(for: [repaired], timeout: 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }
}
