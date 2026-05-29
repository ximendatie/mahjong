import XCTest
@testable import AgentsPet

final class ProcessListReaderTests: XCTestCase {
    func testArgumentsRemovesLeadingPID() {
        XCTAssertEqual(
            ProcessListReader.arguments(from: "  1234 /usr/local/bin/codex --ask"),
            "/usr/local/bin/codex --ask"
        )
    }

    func testTerminalAgentDetectionIncludesCLIsAndExcludesApps() {
        XCTAssertTrue(ProcessListReader.isTerminalAgentProcess("/opt/homebrew/bin/codex run"))
        XCTAssertTrue(ProcessListReader.isTerminalAgentProcess("/usr/local/bin/claude --resume abc"))
        XCTAssertFalse(ProcessListReader.isTerminalAgentProcess("/Applications/Codex.app/Contents/MacOS/Codex"))
        XCTAssertFalse(ProcessListReader.isTerminalAgentProcess("/bin/ps -ax -o pid=,args="))
    }

    func testProviderSpecificProcessDetection() {
        XCTAssertTrue(ProcessListReader.isHermesProcess("/Users/me/.hermes/hermes-agent/hermes serve"))
        XCTAssertTrue(ProcessListReader.isOpenClawProcess("/usr/local/bin/openclaw gateway"))
        XCTAssertFalse(ProcessListReader.isHermesProcess("/Applications/Hermes Agent.app/Contents/MacOS/Hermes Agent"))
        XCTAssertFalse(ProcessListReader.isOpenClawProcess("/Applications/OpenClaw.app/Contents/MacOS/OpenClaw"))
    }
}
