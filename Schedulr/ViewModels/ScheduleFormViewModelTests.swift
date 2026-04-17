import XCTest
@testable import Schedulr

final class ScheduleFormViewModelTests: XCTestCase {

    var viewModel: ScheduleFormViewModel!

    override func setUp() {
        super.setUp()
        viewModel = ScheduleFormViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - earlyReminderDisplayName(for choice: EarlyReminderChoice)

    func testEarlyReminderDisplayName_ChoiceNone() {
        XCTAssertEqual(viewModel.earlyReminderDisplayName(for: .none), "None")
    }

    func testEarlyReminderDisplayName_ChoiceCustom() {
        XCTAssertEqual(viewModel.earlyReminderDisplayName(for: .custom), "Custom")
    }

    func testEarlyReminderDisplayName_ChoicePreset() {
        // Preset internally delegates to earlyReminderDisplayName(_ minutes: Int?)
        // Testing a few preset values
        XCTAssertEqual(viewModel.earlyReminderDisplayName(for: .preset(5)), "5 minutes before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(for: .preset(60)), "1 hour before")
    }

    // MARK: - earlyReminderDisplayName(_ minutes: Int?)

    func testEarlyReminderDisplayName_NilMinutes() {
        XCTAssertEqual(viewModel.earlyReminderDisplayName(nil), "None")
    }

    func testEarlyReminderDisplayName_UnderOneHour() {
        XCTAssertEqual(viewModel.earlyReminderDisplayName(1), "1 minutes before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(5), "5 minutes before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(15), "15 minutes before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(59), "59 minutes before")
    }

    func testEarlyReminderDisplayName_ExactlyOneHour() {
        XCTAssertEqual(viewModel.earlyReminderDisplayName(60), "1 hour before")
    }

    func testEarlyReminderDisplayName_MultipleExactHours() {
        XCTAssertEqual(viewModel.earlyReminderDisplayName(120), "2 hours before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(180), "3 hours before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(1440), "24 hours before") // 1 day
    }

    func testEarlyReminderDisplayName_HoursAndMinutes() {
        XCTAssertEqual(viewModel.earlyReminderDisplayName(61), "1h 1m before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(90), "1h 30m before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(125), "2h 5m before")
        XCTAssertEqual(viewModel.earlyReminderDisplayName(150), "2h 30m before")
    }
}
