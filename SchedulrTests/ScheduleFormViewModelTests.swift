import Foundation

#if canImport(XCTest)
import XCTest
@testable import Schedulr

final class ScheduleFormViewModelTests: XCTestCase {

    func testToggleRepeatWeekday_AddValidWeekday() {
        let vm = ScheduleFormViewModel()
        vm.repeatWeekdays = [1, 2, 3]

        vm.toggleRepeatWeekday(4)
        XCTAssertEqual(vm.repeatWeekdays, [1, 2, 3, 4], "Adding a valid weekday should insert it and keep the array sorted.")
    }

    func testToggleRepeatWeekday_RemoveValidWeekday() {
        let vm = ScheduleFormViewModel()
        vm.repeatWeekdays = [1, 2, 3, 4]

        vm.toggleRepeatWeekday(2)
        XCTAssertEqual(vm.repeatWeekdays, [1, 3, 4], "Removing a valid weekday should delete it and keep the remaining items sorted.")
    }

    func testToggleRepeatWeekday_PreventRemovingLastWeekday() {
        let vm = ScheduleFormViewModel()
        vm.repeatWeekdays = [3]

        vm.toggleRepeatWeekday(3)
        XCTAssertEqual(vm.repeatWeekdays, [3], "Should not allow removing the last remaining weekday.")
    }

    func testToggleRepeatWeekday_IgnoreInvalidWeekday() {
        let vm = ScheduleFormViewModel()
        vm.repeatWeekdays = [1, 2, 3]

        vm.toggleRepeatWeekday(0)
        XCTAssertEqual(vm.repeatWeekdays, [1, 2, 3], "Should ignore weekdays below 1.")

        vm.toggleRepeatWeekday(8)
        XCTAssertEqual(vm.repeatWeekdays, [1, 2, 3], "Should ignore weekdays above 7.")
    }

    func testToggleRepeatWeekday_AddDuplicates() {
        let vm = ScheduleFormViewModel()
        vm.repeatWeekdays = [1, 2, 3]

        // The logic removes the weekday if it exists, so toggling a duplicate actually removes it.
        vm.toggleRepeatWeekday(3)
        XCTAssertEqual(vm.repeatWeekdays, [1, 2], "Toggling an existing weekday should remove it.")
    }

    func testToggleRepeatWeekday_SanitizationOnInvalidState() {
        let vm = ScheduleFormViewModel()
        // Force an invalid state to test the sanitization inside toggleRepeatWeekday
        vm.repeatWeekdays = [0, 1, 2, 2, 3, 8, 9]

        // Toggling a new valid weekday triggers the sanitization pass
        vm.toggleRepeatWeekday(4)
        XCTAssertEqual(vm.repeatWeekdays, [1, 2, 3, 4], "Toggling a weekday should sanitize the array, removing duplicates and invalid weekdays, keeping it sorted.")
    }
}
#endif
