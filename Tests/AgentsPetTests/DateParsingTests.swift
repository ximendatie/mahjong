import XCTest
@testable import AgentsPet

final class DateParsingTests: XCTestCase {
    func testParseDateAcceptsFractionalInternetDateTime() throws {
        let date = try XCTUnwrap(parseDate("2026-05-29T10:11:12.345Z"))
        XCTAssertEqual(Int(date.timeIntervalSince1970), 1_780_049_472)
    }

    func testParseDateAcceptsInternetDateTimeWithoutFractionalSeconds() throws {
        let date = try XCTUnwrap(parseDate("2026-05-29T10:11:12Z"))
        XCTAssertEqual(Int(date.timeIntervalSince1970), 1_780_049_472)
    }

    func testParseDateReturnsNilForMissingOrInvalidValues() {
        XCTAssertNil(parseDate(nil))
        XCTAssertNil(parseDate("not-a-date"))
    }
}
