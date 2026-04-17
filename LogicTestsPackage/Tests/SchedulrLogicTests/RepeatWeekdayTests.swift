import XCTest
@testable import SchedulrLogic

final class RepeatWeekdayTests: XCTestCase {

    func testInitialDefaultState() {
        let initial = Array(1...7)
        XCTAssertEqual(initial, [1, 2, 3, 4, 5, 6, 7])
    }

    func testIsRepeatWeekdaySelected() {
        let selected = [1, 3, 5]
        XCTAssertTrue(WeekdaySelectionLogic.isSelected(1, in: selected))
        XCTAssertTrue(WeekdaySelectionLogic.isSelected(3, in: selected))
        XCTAssertFalse(WeekdaySelectionLogic.isSelected(2, in: selected))
    }

    func testToggleOff() {
        let initial = [1, 2, 3]
        let result = WeekdaySelectionLogic.toggle(1, in: initial)
        XCTAssertEqual(result, [2, 3])
    }

    func testToggleOn() {
        let initial = [2, 3]
        let result = WeekdaySelectionLogic.toggle(1, in: initial)
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testPreventRemovingLastWeekday() {
        let initial = [1]
        let result = WeekdaySelectionLogic.toggle(1, in: initial)
        XCTAssertEqual(result, [1])
    }

    func testToggleInvalidWeekday() {
        let initial = [1, 2, 3]
        let result = WeekdaySelectionLogic.toggle(8, in: initial)
        XCTAssertEqual(result, [1, 2, 3])

        let result2 = WeekdaySelectionLogic.toggle(0, in: initial)
        XCTAssertEqual(result2, [1, 2, 3])
    }

    func testSanitization() {
        XCTAssertEqual(WeekdaySelectionLogic.sanitize([3, 1, 2]), [1, 2, 3])
        XCTAssertEqual(WeekdaySelectionLogic.sanitize([1, 8, 0]), [1])
        XCTAssertEqual(WeekdaySelectionLogic.sanitize([]), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(WeekdaySelectionLogic.sanitize([9]), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(WeekdaySelectionLogic.sanitize([1, 1, 2]), [1, 2])
    }
}
