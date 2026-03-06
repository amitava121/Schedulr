import XCTest
@testable import SchedulrLogic

final class NLPScheduleParserTests: XCTestCase {
    func testParsesDailyPatternAndTagAndPriority() {
        let parsed = NLPScheduleParser.parse("remind me to call mom daily #family urgent")

        XCTAssertEqual(parsed.repeatPattern, .daily)
        XCTAssertEqual(parsed.priority, .high)
        XCTAssertTrue(parsed.tags.contains("family"))
        XCTAssertFalse(parsed.title.isEmpty)
    }

    func testParsesRelativeDateWithTimeSignal() {
        let parsed = NLPScheduleParser.parse("meeting tomorrow at 3pm")

        XCTAssertNotNil(parsed.date)
        XCTAssertTrue(parsed.hasTime)
    }

    func testEmptyInputReturnsDefault() {
        let parsed = NLPScheduleParser.parse("   ")

        XCTAssertEqual(parsed.title, "")
        XCTAssertNil(parsed.date)
        XCTAssertEqual(parsed.repeatPattern, .never)
    }

    func testParsesProvidedTextWithDotTimeAndHighPriority() {
        let parsed = NLPScheduleParser.parse("add reading at 22.00 with alarm high priority")

        XCTAssertEqual(parsed.title, "Reading")
        XCTAssertEqual(parsed.priority, .high)
        XCTAssertTrue(parsed.hasTime)

        if let date = parsed.date {
            let hour = Calendar.current.component(.hour, from: date)
            let minute = Calendar.current.component(.minute, from: date)
            XCTAssertEqual(hour, 22)
            XCTAssertEqual(minute, 0)
        } else {
            XCTFail("Expected parsed date/time for provided text")
        }
    }

    func testAlarmKeywordMapsToAlarmDelivery() {
        let parsed = NLPScheduleParser.parse("add workout tomorrow with alarm")

        XCTAssertEqual(parsed.deliveryOption, .alarm)
    }

    func testAlartMisspellingMapsToAlarmDelivery() {
        let parsed = NLPScheduleParser.parse("add workout tomorrow with alart")

        XCTAssertEqual(parsed.deliveryOption, .alarm)
    }

    func testAlarmTakesPrecedenceOverPushWhenBothPresent() {
        let parsed = NLPScheduleParser.parse("add workout with alarm not push")

        XCTAssertEqual(parsed.deliveryOption, .alarm)
    }

    func testParsesCommaTimeFridayAndEarlyReminderWithTypo() {
        let parsed = NLPScheduleParser.parse("set 23,50 on friday with 5 min eairly reminder")

        XCTAssertTrue(parsed.hasTime)
        XCTAssertEqual(parsed.earlyReminderMinutes, 5)

        if let date = parsed.date {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            let weekday = calendar.component(.weekday, from: date)
            XCTAssertEqual(hour, 23)
            XCTAssertEqual(minute, 50)
            XCTAssertEqual(weekday, 6)
        } else {
            XCTFail("Expected parsed date/time for comma time friday phrase")
        }
    }
}
