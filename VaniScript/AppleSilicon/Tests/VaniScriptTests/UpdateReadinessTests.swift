import XCTest
@testable import VaniScript
@testable import VaniScriptCore

@MainActor
final class UpdateReadinessTests: XCTestCase {

    private func makeStore(
        settingsPersistence: @escaping @Sendable (AppSettings) throws -> Void = { _ in },
        projectsPersistence: @escaping @Sendable ([ProjectRecord]) throws -> Void = { _ in }
    ) -> WorkflowStore {
        WorkflowStore(
            settingsPersistence: settingsPersistence,
            projectsPersistence: projectsPersistence,
            autosaveInterval: .seconds(600),
            startInitialModelScan: false
        )
    }

    func testReadinessSnapshotWhenIdleIsReady() {
        let store = makeStore()

        let snapshot = store.updateReadinessSnapshot

        XCTAssertTrue(snapshot.isReady)
        XCTAssertTrue(snapshot.blockingReasons.isEmpty)
        XCTAssertTrue(store.isReadyForUpdateTermination)
    }

    func testReadinessSnapshotWhenRecordingAudioIsBlocked() {
        let store = makeStore()
        store.isRecordingSystemAudio = true

        let snapshot = store.updateReadinessSnapshot

        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.blockingReasons, [.recordingAudio])
        XCTAssertFalse(store.isReadyForUpdateTermination)
    }

    func testReadinessSnapshotWhenExportingShortsIsBlocked() {
        let store = makeStore()
        store.isExportingShorts = true

        let snapshot = store.updateReadinessSnapshot

        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.blockingReasons, [.exportingShorts])
        XCTAssertFalse(store.isReadyForUpdateTermination)
    }

    func testReadinessSnapshotWhenSaveFailedIsBlocked() {
        let store = makeStore(projectsPersistence: { _ in
            throw NSError(domain: "TestSave", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk I/O error"])
        })

        let prepareResult = store.prepareForUpdateTermination()

        XCTAssertFalse(prepareResult)
        XCTAssertNotNil(store.projectSaveFailure)
        XCTAssertEqual(store.projectSaveFailure, "Disk I/O error")

        let snapshot = store.updateReadinessSnapshot
        XCTAssertFalse(snapshot.isReady)
        XCTAssertTrue(snapshot.blockingReasons.contains(.unsavedChanges("Disk I/O error")))
        XCTAssertFalse(store.isReadyForUpdateTermination)
    }

    func testPrepareForUpdateTerminationExecutesSyncSave() {
        let store = makeStore()
        let success = store.prepareForUpdateTermination()
        XCTAssertTrue(success)
    }

    func testFreezeEditingForUpdateSetsFlag() {
        let store = makeStore()
        XCTAssertFalse(store.isEditingFrozenForUpdate)

        store.freezeEditingForUpdate()

        XCTAssertTrue(store.isEditingFrozenForUpdate)
    }
}
