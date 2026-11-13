import XCTest
@testable import SchedulrLogic

final class MockScheduleState: ScheduleState {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String? = nil
    var scheduledDate: Date = Date()
    var alertDeliveryOption: AlertDeliveryOption = .push
    var priority: SchedulePriority = .none
    var isCompleted: Bool = false
    var repeatPattern: RepeatPattern = .never
    var tags: [String] = []
    var listName: String = "Reminders"
    var urlString: String? = nil
    var earlyReminderMinutes: Int? = nil
    var repeatInterval: Int = 1
    var repeatEndCount: Int = 0
    var additionalReminderMinutes: [Int] = []
    var timeZoneIdentifier: String? = nil
}

final class ScheduleSnapshotTests: XCTestCase {
    func testScheduleSnapshotInitialization() {
        // 1. Setup a state
        let state = MockScheduleState()
        state.id = UUID()
        state.title = "Test Task"
        state.notes = "Test notes"
        state.scheduledDate = Date(timeIntervalSince1970: 1000)
        state.alertDeliveryOption = .alarm
        state.priority = .high
        state.isCompleted = true
        state.repeatPattern = .daily
        state.tags = ["tag1", "tag2"]
        state.listName = "Work"
        state.urlString = "https://example.com"
        state.earlyReminderMinutes = 15
        state.repeatInterval = 2
        state.repeatEndCount = 5
        state.additionalReminderMinutes = [30, 60]
        state.timeZoneIdentifier = "America/New_York"

        // 2. Initialize snapshot
        let snapshot = ScheduleSnapshot(from: state)

        // 3. Verify snapshot properties
        XCTAssertEqual(snapshot.id, state.id)
        XCTAssertEqual(snapshot.title, "Test Task")
        XCTAssertEqual(snapshot.notes, "Test notes")
        XCTAssertEqual(snapshot.scheduledDate, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(snapshot.alertOption, AlertDeliveryOption.alarm.rawValue)
        XCTAssertEqual(snapshot.priority, SchedulePriority.high.rawValue)
        XCTAssertTrue(snapshot.isCompleted)
        XCTAssertEqual(snapshot.repeatPattern, RepeatPattern.daily.rawValue)
        XCTAssertEqual(snapshot.tags, ["tag1", "tag2"])
        XCTAssertEqual(snapshot.calendar, "Work")
        XCTAssertEqual(snapshot.urlString, "https://example.com")
        XCTAssertEqual(snapshot.reminderMinutesBefore, 15)
        XCTAssertEqual(snapshot.repeatInterval, 2)
        XCTAssertEqual(snapshot.repeatEndCount, 5)
        XCTAssertEqual(snapshot.additionalReminderMinutes, [30, 60])
        XCTAssertEqual(snapshot.timeZoneIdentifier, "America/New_York")
    }

    func testScheduleSnapshotApply() {
        // 1. Create a snapshot with specific data
        let stateToSnapshot = MockScheduleState()
        stateToSnapshot.title = "Source Task"
        stateToSnapshot.notes = "Source Notes"
        stateToSnapshot.scheduledDate = Date(timeIntervalSince1970: 2000)
        stateToSnapshot.alertDeliveryOption = .push
        stateToSnapshot.priority = .medium
        stateToSnapshot.isCompleted = false
        stateToSnapshot.repeatPattern = .weekly
        stateToSnapshot.tags = ["urgent"]
        stateToSnapshot.listName = "Personal"
        stateToSnapshot.urlString = "https://test.com"
        stateToSnapshot.earlyReminderMinutes = 5
        stateToSnapshot.repeatInterval = 3
        stateToSnapshot.repeatEndCount = 10
        stateToSnapshot.additionalReminderMinutes = [10]
        stateToSnapshot.timeZoneIdentifier = "Europe/London"

        let snapshot = ScheduleSnapshot(from: stateToSnapshot)

        // 2. Create a target state with different initial data
        let targetState = MockScheduleState()
        targetState.title = "Old Title"
        targetState.priority = .low
        targetState.isCompleted = true

        // 3. Apply snapshot to target state
        snapshot.apply(to: targetState)

        // 4. Verify target state has been updated correctly
        XCTAssertEqual(targetState.title, "Source Task")
        XCTAssertEqual(targetState.notes, "Source Notes")
        XCTAssertEqual(targetState.scheduledDate, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(targetState.alertDeliveryOption, .push)
        XCTAssertEqual(targetState.priority, .medium)
        XCTAssertFalse(targetState.isCompleted)
        XCTAssertEqual(targetState.repeatPattern, .weekly)
        XCTAssertEqual(targetState.tags, ["urgent"])
        XCTAssertEqual(targetState.listName, "Personal")
        XCTAssertEqual(targetState.urlString, "https://test.com")
        XCTAssertEqual(targetState.earlyReminderMinutes, 5)
        XCTAssertEqual(targetState.repeatInterval, 3)
        XCTAssertEqual(targetState.repeatEndCount, 10)
        XCTAssertEqual(targetState.additionalReminderMinutes, [10])
        XCTAssertEqual(targetState.timeZoneIdentifier, "Europe/London")
    }

    func testScheduleSnapshotApplyWithNilOptionalValues() {
        let stateToSnapshot = MockScheduleState()
        stateToSnapshot.notes = nil
        stateToSnapshot.urlString = nil
        stateToSnapshot.earlyReminderMinutes = nil
        stateToSnapshot.timeZoneIdentifier = nil
        stateToSnapshot.tags = []
        stateToSnapshot.additionalReminderMinutes = []

        let snapshot = ScheduleSnapshot(from: stateToSnapshot)

        let targetState = MockScheduleState()
        targetState.notes = "Should be cleared"
        targetState.urlString = "Should be cleared"
        targetState.earlyReminderMinutes = 10
        targetState.timeZoneIdentifier = "UTC"
        targetState.tags = ["old"]
        targetState.additionalReminderMinutes = [15]

        snapshot.apply(to: targetState)

        XCTAssertNil(targetState.notes)
        XCTAssertNil(targetState.urlString)
        XCTAssertNil(targetState.earlyReminderMinutes)
        XCTAssertNil(targetState.timeZoneIdentifier)
        XCTAssertTrue(targetState.tags.isEmpty)
        XCTAssertTrue(targetState.additionalReminderMinutes.isEmpty)
    }

    func testScheduleSnapshotApplyWithInvalidRawValues() {
        // Test fallback defaults if a raw value somehow becomes invalid
        // E.g., from an older version or corrupted state.
        // We simulate this by directly initializing a snapshot using a JSONDecoder or manually
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "title": "Title",
            "scheduledDate": 0,
            "alertOption": "invalidOption",
            "priority": 999,
            "isCompleted": false,
            "repeatPattern": "invalidPattern",
            "tags": [],
            "calendar": "Calendar",
            "repeatInterval": 1,
            "repeatEndCount": 0,
            "additionalReminderMinutes": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try! decoder.decode(ScheduleSnapshot.self, from: json)

        let targetState = MockScheduleState()
        targetState.alertDeliveryOption = .alarm
        targetState.priority = .high
        targetState.repeatPattern = .daily

        snapshot.apply(to: targetState)

        // Should fallback to default values for invalid enums
        XCTAssertEqual(targetState.alertDeliveryOption, .push, "Fallback should be .push")
        XCTAssertEqual(targetState.priority, .none, "Fallback should be .none")
        XCTAssertEqual(targetState.repeatPattern, .never, "Fallback should be .never")
    }
}
