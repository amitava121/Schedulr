import XCTest
@testable import SchedulrLogic

final class JSONSerializationUtilsTests: XCTestCase {
    func testStringMapping() {
        let value = "hello"
        let result = JSONSerializationUtils.jsonCompatibleValue(from: value) as? String
        XCTAssertEqual(result, "hello")
    }

    func testIntMapping() {
        let value = 42
        let result = JSONSerializationUtils.jsonCompatibleValue(from: value) as? Int
        XCTAssertEqual(result, 42)
    }

    func testDoubleMapping() {
        let value = 3.14
        let result = JSONSerializationUtils.jsonCompatibleValue(from: value) as? Double
        XCTAssertEqual(result, 3.14)

        let infinite = Double.infinity
        let nilResult = JSONSerializationUtils.jsonCompatibleValue(from: infinite)
        XCTAssertNil(nilResult)
    }

    func testBoolMapping() {
        let value = true
        let result = JSONSerializationUtils.jsonCompatibleValue(from: value) as? Bool
        XCTAssertTrue(result ?? false)
    }

    func testDateMapping() {
        let date = Date(timeIntervalSince1970: 1600000000.5)
        let result = JSONSerializationUtils.jsonCompatibleValue(from: date) as? String
        XCTAssertEqual(result, JSONSerializationUtils.iso8601WithFractionalSecondsFormatter.string(from: date))
    }

    func testNSNumberMapping() {
        let value = NSNumber(value: 123)
        let result = JSONSerializationUtils.jsonCompatibleValue(from: value) as? NSNumber
        XCTAssertEqual(result, value)
    }

    func testNSNullMapping() {
        let value = NSNull()
        let result = JSONSerializationUtils.jsonCompatibleValue(from: value)
        XCTAssertTrue(result is NSNull)
    }

    func testArrayMapping() {
        let date = Date(timeIntervalSince1970: 1000)
        let array: [Any] = [1, "two", date, NSNull(), Double.infinity]

        let result = JSONSerializationUtils.jsonCompatibleValue(from: array) as? [Any]
        XCTAssertNotNil(result)

        XCTAssertEqual(result?[0] as? Int, 1)
        XCTAssertEqual(result?[1] as? String, "two")
        XCTAssertEqual(result?[2] as? String, JSONSerializationUtils.iso8601WithFractionalSecondsFormatter.string(from: date))
        XCTAssertTrue(result?[3] is NSNull)
        XCTAssertTrue(result?[4] is NSNull) // Because double.infinity is mapped to nil which becomes NSNull in array
    }

    func testDictionaryMapping() {
        let date = Date(timeIntervalSince1970: 2000)
        let dictionary: [String: Any] = [
            "int": 42,
            "string": "value",
            "date": date,
            "null": NSNull(),
            "invalid": Double.infinity,
            "nested": ["key": "nestedValue"]
        ]

        let result = JSONSerializationUtils.jsonCompatibleValue(from: dictionary) as? [String: Any]
        XCTAssertNotNil(result)

        XCTAssertEqual(result?["int"] as? Int, 42)
        XCTAssertEqual(result?["string"] as? String, "value")
        XCTAssertEqual(result?["date"] as? String, JSONSerializationUtils.iso8601WithFractionalSecondsFormatter.string(from: date))
        XCTAssertTrue(result?["null"] is NSNull)
        XCTAssertNil(result?["invalid"]) // Dictionary omits nil values

        let nested = result?["nested"] as? [String: Any]
        XCTAssertEqual(nested?["key"] as? String, "nestedValue")
    }

    func testCustomTransform() {
        struct CustomType {
            let id: String
        }

        let custom = CustomType(id: "abc")
        let array: [Any] = [1, custom]

        let result = JSONSerializationUtils.jsonCompatibleValue(from: array) { value in
            if let c = value as? CustomType {
                return c.id
            }
            return nil
        } as? [Any]

        XCTAssertNotNil(result)
        XCTAssertEqual(result?[0] as? Int, 1)
        XCTAssertEqual(result?[1] as? String, "abc")
    }
}
