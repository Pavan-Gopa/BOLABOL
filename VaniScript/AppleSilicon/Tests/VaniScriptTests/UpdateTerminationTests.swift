import XCTest
@testable import VaniScript
@testable import VaniScriptCore

@MainActor
final class MockReadinessProvider: UpdateReadinessProviding {
    var snapshotToReturn: UpdateReadinessSnapshot = .ready
    var prepareSuccess: Bool = true
    var didFreeze: Bool = false
    var prepareCallCount: Int = 0

    var updateReadinessSnapshot: UpdateReadinessSnapshot {
        snapshotToReturn
    }

    var isReadyForUpdateTermination: Bool {
        snapshotToReturn.isReady
    }

    var currentProjectRevision: String {
        "mock-rev-1"
    }

    func prepareForUpdateTermination() -> Bool {
        prepareCallCount += 1
        return prepareSuccess
    }

    func freezeEditingForUpdate() {
        didFreeze = true
    }
}

@MainActor
final class UpdateTerminationTests: XCTestCase {
    nonisolated(unsafe) var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    func testTerminationPreparationSuccess() {
        let provider = MockReadinessProvider()
        let coordinator = UpdateTerminationCoordinator(
            readinessProvider: provider,
            backupDirectory: tempDirectory.appendingPathComponent("Backups")
        )

        let result = coordinator.prepareAndValidateTermination()

        XCTAssertEqual(result, .readyToTerminate)
        XCTAssertTrue(provider.didFreeze)
        XCTAssertEqual(provider.prepareCallCount, 1)
    }

    func testTerminationBlockedByActiveOperation() {
        let provider = MockReadinessProvider()
        provider.snapshotToReturn = .blocked(by: [.recordingAudio])
        let coordinator = UpdateTerminationCoordinator(
            readinessProvider: provider,
            backupDirectory: tempDirectory.appendingPathComponent("Backups")
        )

        let result = coordinator.prepareAndValidateTermination()

        XCTAssertEqual(result, .blocked(reasons: [.recordingAudio]))
        XCTAssertFalse(provider.didFreeze)
        XCTAssertEqual(provider.prepareCallCount, 0)
    }

    func testTerminationBlockedBySaveFailure() {
        let provider = MockReadinessProvider()
        provider.prepareSuccess = false
        let coordinator = UpdateTerminationCoordinator(
            readinessProvider: provider,
            backupDirectory: tempDirectory.appendingPathComponent("Backups")
        )

        let result = coordinator.prepareAndValidateTermination()

        if case .saveFailed = result {
            // expected
        } else {
            XCTFail("Expected saveFailed, got \(result)")
        }
        XCTAssertFalse(provider.didFreeze)
    }

    func testInstallUpdateBlockedKeepsAppOpen() {
        let provider = MockReadinessProvider()
        provider.snapshotToReturn = .blocked(by: [.exportingShorts])
        let driver = UpdateUserDriver()
        let coordinator = UpdateCoordinator(driver: driver, readinessProvider: provider)
        driver.coordinator = coordinator

        coordinator.installUpdate()

        if case .failed(let error) = coordinator.phase {
            XCTAssertTrue(error.message.contains("Shorts/Reels video export is in progress"))
        } else {
            XCTFail("Expected failed phase, got \(coordinator.phase)")
        }
    }

    func testRetryTerminationRechecksReadiness() {
        let provider = MockReadinessProvider()
        let driver = UpdateUserDriver()
        let coordinator = UpdateCoordinator(driver: driver, readinessProvider: provider)
        driver.coordinator = coordinator

        var retryClosureCalled = false
        driver.showInstallingUpdate(withApplicationTerminated: false) {
            retryClosureCalled = true
        }

        // 1. Blocked state
        provider.snapshotToReturn = .blocked(by: [.recordingAudio])
        driver.retryTerminatingApplication()
        XCTAssertFalse(retryClosureCalled)
        if case .failed = coordinator.phase {
            // expected
        } else {
            XCTFail("Expected failed phase on blocked retry")
        }

        // 2. Ready state
        provider.snapshotToReturn = .ready
        driver.retryTerminatingApplication()
        XCTAssertTrue(retryClosureCalled)
    }

    func testReceiptStoreRoundTripAndPostRelaunchSurfacing() throws {
        let receiptURL = tempDirectory.appendingPathComponent("update_receipt.json")
        let receiptStore = UpdateReceiptStore(fileURL: receiptURL)

        try receiptStore.recordUpdate(
            previousVersion: "1.0.0",
            previousBuild: "100",
            targetVersion: "1.1.0",
            targetBuild: "110"
        )

        let loaded = receiptStore.loadReceipt()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.previousVersion, "1.0.0")
        XCTAssertEqual(loaded?.installedVersion, "1.1.0")

        let store = WorkflowStore()
        let driver = UpdateUserDriver()
        let updateCoordinator = UpdateCoordinator(driver: driver, receiptStore: receiptStore)
        updateCoordinator.checkAndSurfacePostRelaunchReceipt(workflowStore: store)

        XCTAssertEqual(store.statusMessage, "VaniScript was successfully updated to version 1.1.0.")
        XCTAssertNil(receiptStore.loadReceipt()) // should be cleared after surfacing
    }
}
