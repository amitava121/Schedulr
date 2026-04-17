import XCTest
@testable import Schedulr

final class ScheduleFormViewModelTests: XCTestCase {
    var sut: ScheduleFormViewModel!

    override func setUp() {
        super.setUp()
        sut = ScheduleFormViewModel()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testEarlyReminderDisplayName_WithNilMinutes_ReturnsNone() {
        let result = sut.earlyReminderDisplayName(nil)
        XCTAssertEqual(result, "None")
    }

    func testEarlyReminderDisplayName_WithLessThan60Minutes_ReturnsMinutes() {
        XCTAssertEqual(sut.earlyReminderDisplayName(0), "0 minutes before")
        XCTAssertEqual(sut.earlyReminderDisplayName(1), "1 minutes before")
        XCTAssertEqual(sut.earlyReminderDisplayName(15), "15 minutes before")
        XCTAssertEqual(sut.earlyReminderDisplayName(45), "45 minutes before")
        XCTAssertEqual(sut.earlyReminderDisplayName(59), "59 minutes before")
    }

    func testEarlyReminderDisplayName_WithExactHours_ReturnsHours() {
        XCTAssertEqual(sut.earlyReminderDisplayName(60), "1 hour before")
        XCTAssertEqual(sut.earlyReminderDisplayName(120), "2 hours before")
        XCTAssertEqual(sut.earlyReminderDisplayName(1440), "24 hours before")
    }

    func testEarlyReminderDisplayName_WithMixedHoursAndMinutes_ReturnsFormattedString() {
        XCTAssertEqual(sut.earlyReminderDisplayName(61), "1h 1m before")
        XCTAssertEqual(sut.earlyReminderDisplayName(65), "1h 5m before")
        XCTAssertEqual(sut.earlyReminderDisplayName(90), "1h 30m before")
        XCTAssertEqual(sut.earlyReminderDisplayName(150), "2h 30m before")
        XCTAssertEqual(sut.earlyReminderDisplayName(1441), "24h 1m before")
    }
}
