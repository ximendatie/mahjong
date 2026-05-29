import XCTest
@testable import AgentsPet

final class CodexLocalProviderTests: XCTestCase {
    private var temporaryHome: URL!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentsPetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryHome {
            try? FileManager.default.removeItem(at: temporaryHome)
        }
        temporaryHome = nil
    }

    func testFetchTasksReadsCodexIndexAndSessionMetadata() async throws {
        let sessionID = "11111111-2222-3333-4444-555555555555"
        let codexDirectory = temporaryHome.appendingPathComponent(".codex", isDirectory: true)
        let sessionsDirectory = codexDirectory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let index = """
        {"id":"\(sessionID)","thread_name":"Open source polish","updated_at":"2026-05-29T10:00:00Z"}
        """
        try index.write(
            to: codexDirectory.appendingPathComponent("session_index.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let session = """
        {"timestamp":"2026-05-29T10:00:01Z","payload":{"cwd":"\(temporaryHome.path)/agentspet","model":"gpt-test"}}
        {"timestamp":"2026-05-29T10:00:02Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-05-29T10:00:03Z","payload":{"info":{"total_token_usage":{"total_tokens":42}}}}
        """
        let sessionURL = sessionsDirectory.appendingPathComponent("rollout-\(sessionID).jsonl")
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let tasks = await CodexLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "codex:\(sessionID)")
        XCTAssertEqual(task.title, "Open source polish")
        XCTAssertEqual(task.agent, "Codex")
        XCTAssertEqual(task.model, "gpt-test")
        XCTAssertEqual(task.tokenUsage, 42)
        XCTAssertEqual(task.status, .running)
        XCTAssertEqual(
            task.openURL?.resolvingSymlinksInPath().path,
            sessionURL.resolvingSymlinksInPath().path
        )
    }

    func testFetchTasksReturnsEmptyWhenIndexIsMissing() async {
        let tasks = await CodexLocalProvider(homeDirectory: temporaryHome).fetchTasks()
        XCTAssertTrue(tasks.isEmpty)
    }
}
