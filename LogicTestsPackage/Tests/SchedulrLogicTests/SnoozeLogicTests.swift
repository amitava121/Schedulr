import XCTest
@testable import SchedulrLogic

final class SnoozeLogicTests: XCTestCase {

    func testSnoozeDisplayNameForPreset() {
        let presetChoice = SnoozeChoice.preset(10)
        let displayName = SnoozeLogic.snoozeDisplayName(for: presetChoice)
        XCTAssertEqual(displayName, "10 min")

        let presetChoiceTwo = SnoozeChoice.preset(5)
        let displayNameTwo = SnoozeLogic.snoozeDisplayName(for: presetChoiceTwo)
        XCTAssertEqual(displayNameTwo, "5 min")
    }

    func testSnoozeDisplayNameForCustom() {
        let customChoice = SnoozeChoice.custom
        let displayName = SnoozeLogic.snoozeDisplayName(for: customChoice)
        XCTAssertEqual(displayName, "Custom Time")
    }

}
