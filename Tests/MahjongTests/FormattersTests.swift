import XCTest
@testable import mahjong

final class FormattersTests: XCTestCase {
    func testTokensUsesLargerUnitsForLargeValues() {
        XCTAssertEqual(Formatters.tokens(999), "999")
        XCTAssertEqual(Formatters.tokens(1_115_200), "1.1M")
        XCTAssertEqual(Formatters.tokens(192_923_500), "192.9M")
        XCTAssertEqual(Formatters.tokens(1_260_000_000), "1.3B")
        XCTAssertEqual(Formatters.tokens(2_500_000_000_000), "2.5T")
    }
}
