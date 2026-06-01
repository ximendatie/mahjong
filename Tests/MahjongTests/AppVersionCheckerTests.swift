import XCTest
@testable import mahjong

final class AppVersionCheckerTests: XCTestCase {
    func testNormalizedVersionStripsTagPrefix() {
        XCTAssertEqual(AppVersionChecker.normalizedVersion("v0.5.1"), "0.5.1")
        XCTAssertEqual(AppVersionChecker.normalizedVersion("  v1.2.3  "), "1.2.3")
    }

    func testCompareVersionsUsesNumericOrdering() {
        XCTAssertEqual(AppVersionChecker.compareVersions("0.5.10", "0.5.2"), .orderedDescending)
        XCTAssertEqual(AppVersionChecker.compareVersions("1.0.0", "1.0"), .orderedSame)
        XCTAssertEqual(AppVersionChecker.compareVersions("0.5.1", "0.6.0"), .orderedAscending)
    }

    func testReleaseTagNameFromGitHubReleaseURL() throws {
        let url = try XCTUnwrap(URL(string: "https://github.com/ximendatie/mahjong/releases/tag/v0.5.1"))

        XCTAssertEqual(AppVersionChecker.releaseTagName(from: url), "v0.5.1")
    }
}
