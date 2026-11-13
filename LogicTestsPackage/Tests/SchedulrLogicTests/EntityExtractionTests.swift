import XCTest
@testable import SchedulrLogic

final class EntityExtractionTests: XCTestCase {

    enum MockPriority: String, CaseIterable {
        case none = "None"
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        var displayName: String { rawValue }
    }

    func testExtractEmptyIdentifiers() {
        let identifiers: [String] = []
        let entities = EntityExtraction.extract(
            identifiers: identifiers,
            allEntities: MockPriority.allCases,
            idProvider: { $0.displayName }
        )
        XCTAssertTrue(entities.isEmpty, "Extracting entities for empty identifiers should return empty array")
    }

    func testExtractSingleMatch() {
        let identifiers = ["Low"]
        let entities = EntityExtraction.extract(
            identifiers: identifiers,
            allEntities: MockPriority.allCases,
            idProvider: { $0.displayName }
        )
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first, .low)
    }

    func testExtractMultipleMatchesPreservesOrder() {
        let identifiers = ["High", "Low", "None"]
        let entities = EntityExtraction.extract(
            identifiers: identifiers,
            allEntities: MockPriority.allCases,
            idProvider: { $0.displayName }
        )
        XCTAssertEqual(entities.count, 3)
        XCTAssertEqual(entities[0], .high)
        XCTAssertEqual(entities[1], .low)
        XCTAssertEqual(entities[2], .none)
    }

    func testExtractDuplicateMatches() {
        let identifiers = ["Medium", "Medium", "High"]
        let entities = EntityExtraction.extract(
            identifiers: identifiers,
            allEntities: MockPriority.allCases,
            idProvider: { $0.displayName }
        )
        XCTAssertEqual(entities.count, 3)
        XCTAssertEqual(entities[0], .medium)
        XCTAssertEqual(entities[1], .medium)
        XCTAssertEqual(entities[2], .high)
    }

    func testExtractInvalidIdentifierIgnored() {
        let identifiers = ["High", "InvalidPriority", "Low"]
        let entities = EntityExtraction.extract(
            identifiers: identifiers,
            allEntities: MockPriority.allCases,
            idProvider: { $0.displayName }
        )
        XCTAssertEqual(entities.count, 2)
        XCTAssertEqual(entities[0], .high)
        XCTAssertEqual(entities[1], .low)
    }

    func testExtractCaseSensitivity() {
        // According to the current pure logic implementation, it exactly matches `idProvider`.
        // If the identifier case is wrong, it should be ignored.
        let identifiers = ["high", "Low"]
        let entities = EntityExtraction.extract(
            identifiers: identifiers,
            allEntities: MockPriority.allCases,
            idProvider: { $0.displayName }
        )
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities[0], .low)
    }
}
