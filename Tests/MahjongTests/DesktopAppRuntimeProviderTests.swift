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

    func testMiraBundleIdentifierCreatesRuntime() throws {
        let runtime = try XCTUnwrap(DesktopAppRuntimeProvider.runtime(bundleIdentifier: "net.byteintl.mira"))

        XCTAssertEqual(runtime.id, "desktop:mira")
        XCTAssertEqual(runtime.name, "Mira")
        XCTAssertEqual(runtime.provider, "Mira")
        XCTAssertEqual(runtime.providerID, .desktopApps)
        XCTAssertEqual(runtime.kind, .desktopApp)
        XCTAssertEqual(runtime.bundleIdentifier, "net.byteintl.mira")
        XCTAssertEqual(runtime.iconBundleIdentifier, AgentRuntimeIconBundle.mira)
        XCTAssertNil(runtime.iconResourceName)
        XCTAssertTrue(runtime.summary.contains("不读取工程或会话内容"))
    }

    func testTraeCNDesktopProcessIsDetected() {
        let processLine = "74500 /Applications/Trae CN.app/Contents/MacOS/Electron"

        XCTAssertTrue(ProcessListReader.isTraeCNDesktopProcess(processLine[...]))
    }

    func testMiraDesktopProcessIsDetected() {
        let processLine = "96946 /Applications/Mira.app/Contents/MacOS/Mira"

        XCTAssertTrue(ProcessListReader.isMiraDesktopProcess(processLine[...]))
    }

    func testMiraHelperProcessIsIgnored() {
        let processLine = "97189 /Applications/Mira.app/Contents/Frameworks/Mira Helper (GPU).app/Contents/MacOS/Mira Helper (GPU)"

        XCTAssertFalse(ProcessListReader.isMiraDesktopProcess(processLine[...]))
    }

    func testUnknownBundleIdentifierIsIgnored() {
        XCTAssertNil(DesktopAppRuntimeProvider.runtime(bundleIdentifier: "example.unknown.Agent"))
    }
}
