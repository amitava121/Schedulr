import XCTest
@testable import SchedulrLogic

final class SyncConflictResolverTests: XCTestCase {
    private func makeDelta(
        id: String = UUID().uuidString,
        title: String = "Task",
        notes: String? = "n",
        scheduledDate: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        excluded: [Date] = []
    ) -> ScheduleDelta {
        ScheduleDelta(
            scheduleID: id,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            lastModifiedDeviceID: "device-a",
            title: title,
            notes: notes,
            scheduledDate: scheduledDate,
            excludedOccurrenceDates: excluded,
            tags: tags,
            syncVersion: 1,
            deviceID: "device-a",
            clientUpdatedAt: updatedAt
        )
    }

    func testUserVisibleConflictFalseForMergeableFieldsOnly() {
        let now = Date()
        let local = makeDelta(title: "Task", notes: "n", scheduledDate: now, updatedAt: now, tags: ["a"])
        let remote = makeDelta(id: local.scheduleID, title: "Task", notes: "n", scheduledDate: now, updatedAt: now, tags: ["b"])

        XCTAssertFalse(SyncConflictResolver.isConflictUserVisible(local: local, remote: remote))
    }

    func testUserVisibleConflictTrueForTitleDiff() {
        let now = Date()
        let local = makeDelta(title: "Task A", scheduledDate: now, updatedAt: now)
        let remote = makeDelta(id: local.scheduleID, title: "Task B", scheduledDate: now, updatedAt: now)

        XCTAssertTrue(SyncConflictResolver.isConflictUserVisible(local: local, remote: remote))
    }

    func testLocalWithUnionMergesTagsAndExcludedDates() {
        let now = Date()
        let local = makeDelta(title: "Task", scheduledDate: now, updatedAt: now, tags: ["a"], excluded: [now])
        let remote = makeDelta(id: local.scheduleID, title: "Task", scheduledDate: now, updatedAt: now, tags: ["b"], excluded: [now.addingTimeInterval(86400)])

        let merged = SyncConflictResolver.localWithUnion(local: local, remote: remote)

        XCTAssertEqual(Set(merged.tags), Set(["a", "b"]))
        XCTAssertEqual(Set(merged.excludedOccurrenceDates.map(\.startOfDay)), Set([now.startOfDay, now.addingTimeInterval(86400).startOfDay]))
    }

    func testConflictSummaryListsChangedFields() {
        let now = Date()
        let local = makeDelta(title: "One", notes: "A", scheduledDate: now, updatedAt: now)
        let remote = makeDelta(id: local.scheduleID, title: "Two", notes: "B", scheduledDate: now.addingTimeInterval(3600), updatedAt: now)

        let summary = SyncConflictResolver.conflictSummary(local: local, remote: remote)

        XCTAssertTrue(summary.contains("Title"))
        XCTAssertTrue(summary.contains("Date"))
        XCTAssertTrue(summary.contains("Notes"))
    }

    private func makeSchedule(
        id: UUID = UUID(),
        title: String = "Task",
        scheduledDate: Date,
        updatedAt: Date,
        tags: [String] = [],
        excluded: [Date] = [],
        notes: String? = nil
    ) -> Schedule {
        Schedule(
            id: id,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            lastModifiedDeviceID: "device-a",
            syncVersion: 2,
            lastSyncedVersion: 1,
            title: title,
            notes: notes,
            scheduledDate: scheduledDate,
            excludedOccurrenceDates: excluded,
            tags: tags
        )
    }

    func testResolveBlobRestoreConflictMergesSameIdentity() {
        let now = Date()
        let id = UUID()
        let local = makeSchedule(id: id, title: "Gym", scheduledDate: now, updatedAt: now, tags: ["health"], excluded: [now])
        let remote = makeSchedule(id: id, title: "Gym", scheduledDate: now, updatedAt: now.addingTimeInterval(10), tags: ["weekly"], excluded: [now.addingTimeInterval(86400)])

        let action = SyncConflictResolver.resolveBlobRestoreConflict(localSchedule: local, remoteSchedule: remote)

        switch action {
        case .merge(let merged):
            XCTAssertEqual(Set(merged.tags), Set(["health", "weekly"]))
            XCTAssertEqual(Set(merged.excludedOccurrenceDates.map(\.startOfDay)), Set([now.startOfDay, now.addingTimeInterval(86400).startOfDay]))
        default:
            XCTFail("Expected merge action for same title + scheduledDate")
        }
    }

    func testResolveBlobRestoreConflictKeepsNewerSideWhenDifferentIdentity() {
        let now = Date()
        let local = makeSchedule(title: "One", scheduledDate: now, updatedAt: now)
        let remote = makeSchedule(title: "Two", scheduledDate: now.addingTimeInterval(3600), updatedAt: now.addingTimeInterval(120))

        let action = SyncConflictResolver.resolveBlobRestoreConflict(localSchedule: local, remoteSchedule: remote)

        switch action {
        case .keepRemote:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected keepRemote for newer remote with different identity")
        }
    }

    func testResolveBlobRestoreConflictKeepsLocalWhenNewerWithDifferentIdentity() {
        let now = Date()
        let local = makeSchedule(title: "One", scheduledDate: now.addingTimeInterval(3600), updatedAt: now.addingTimeInterval(120))
        let remote = makeSchedule(title: "Two", scheduledDate: now, updatedAt: now)

        let action = SyncConflictResolver.resolveBlobRestoreConflict(localSchedule: local, remoteSchedule: remote)

        switch action {
        case .keepLocal:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected keepLocal for newer local with different identity")
        }
    }

    func testResolveBlobRestoreConflictKeepsLocalWhenTimestampsEqualWithDifferentIdentity() {
        let now = Date()
        let local = makeSchedule(title: "One", scheduledDate: now.addingTimeInterval(3600), updatedAt: now)
        let remote = makeSchedule(title: "Two", scheduledDate: now, updatedAt: now)

        let action = SyncConflictResolver.resolveBlobRestoreConflict(localSchedule: local, remoteSchedule: remote)

        switch action {
        case .keepLocal:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected keepLocal for equal timestamps with different identity")
        }
    }
}

final class SettingsSyncLogicTests: XCTestCase {
    func testShouldApplyRemoteSettingsWhenRemoteIsNewer() {
        let local = Date(timeIntervalSince1970: 1_000)
        let remote = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(SettingsSyncLogic.shouldApplyRemoteSettings(localUpdatedAt: local, remoteUpdatedAt: remote))
    }

    func testShouldNotApplyRemoteSettingsWhenRemoteIsOlder() {
        let local = Date(timeIntervalSince1970: 2_000)
        let remote = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(SettingsSyncLogic.shouldApplyRemoteSettings(localUpdatedAt: local, remoteUpdatedAt: remote))
    }

    func testShouldNotApplyRemoteSettingsWhenRemoteTimestampMissing() {
        let local = Date(timeIntervalSince1970: 2_000)
        XCTAssertFalse(SettingsSyncLogic.shouldApplyRemoteSettings(localUpdatedAt: local, remoteUpdatedAt: nil))
    }
}
