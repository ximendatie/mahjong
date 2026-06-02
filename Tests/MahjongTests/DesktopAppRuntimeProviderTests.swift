import XCTest
@testable import mahjong

final class DesktopAppRuntimeProviderTests: XCTestCase {
    func testTraeCNBundleIdentifierCreatesRuntime() throws {
        let runtime = try XCTUnwrap(DesktopAppRuntimeProvider.runtime(bundleIdentifier: "cn.trae.app"))

        XCTAssertEqual(runtime.id, "desktop:trae")
        XCTAssertEqual(runtime.name, "Trae CN")
        XCTAssertEqual(runtime.provider, "Trae")
        XCTAssertEqual(runtime.providerID, .desktopApps)
        XCTAssertEqual(runtime.kind, .desktopApp)
        XCTAssertEqual(runtime.bundleIdentifier, "cn.trae.app")
        XCTAssertEqual(runtime.iconBundleIdentifier, AgentRuntimeIconBundle.traeCN)
        XCTAssertEqual(runtime.iconResourceName, "AgentIcons/trae-cn")
        XCTAssertTrue(runtime.summary.contains("不读取工程或会话内容"))
    }

    func testTraeCNHelperBundleIdentifierCreatesRuntime() throws {
        let runtime = try XCTUnwrap(DesktopAppRuntimeProvider.runtime(bundleIdentifier: "cn.trae.app.helper"))

        XCTAssertEqual(runtime.id, "desktop:trae")
        XCTAssertEqual(runtime.name, "Trae CN")
        XCTAssertEqual(runtime.bundleIdentifier, "cn.trae.app.helper")
        XCTAssertEqual(runtime.iconBundleIdentifier, AgentRuntimeIconBundle.traeCN)
        XCTAssertEqual(runtime.iconResourceName, "AgentIcons/trae-cn")
    }

    func testTraeCNDesktopProcessIsDetected() {
        let processLine = "74500 /Applications/Trae CN.app/Contents/MacOS/Electron"

        XCTAssertTrue(ProcessListReader.isTraeCNDesktopProcess(processLine[...]))
    }

    func testUnknownBundleIdentifierIsIgnored() {
        XCTAssertNil(DesktopAppRuntimeProvider.runtime(bundleIdentifier: "example.unknown.Agent"))
    }
}
