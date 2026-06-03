import XCTest
@testable import mahjong

final class TraeCNLocalProviderTests: XCTestCase {
    func testLogLineCreatesEventWithoutReadingMessageText() throws {
        let line = """
        2026-06-02T16:10:53.123430+08:00  INFO process_ipc_request:route:chat:do_chat: session_id=6a1e57868662d364fffb938d task_id=6a1e900c8662d364fffb944c message_id=6a1e900c8662d364fffb944b
        """

        let event = try XCTUnwrap(TraeCNLocalProvider.event(from: line[...]))

        XCTAssertEqual(event.sessionID, "6a1e57868662d364fffb938d")
        XCTAssertEqual(event.taskID, "6a1e900c8662d364fffb944c")
    }

    func testFetchTasksReadsTraeCNAgentLogMetadata() async throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mahjong-trae-tests-\(UUID().uuidString)", isDirectory: true)
        let logDirectory = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Trae CN", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("20260602T160000", isDirectory: true)
            .appendingPathComponent("Modular", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logURL = logDirectory.appendingPathComponent("ai-agent_0_1780307835419_stdout.log")
        try """
        \(timestamp)  INFO unrelated log line
        \(timestamp)  INFO process_ipc_request:route:chat:do_chat: session_id=6a1e57868662d364fffb938d task_id=6a1e900c8662d364fffb944c message_id=6a1e900c8662d364fffb944b
        """.write(to: logURL, atomically: true, encoding: .utf8)

        let provider = TraeCNLocalProvider(homeDirectory: home)
        let tasks = await provider.fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "trae-cn:6a1e57868662d364fffb938d")
        XCTAssertEqual(task.title, "Trae CN 会话 6a1e5786")
        XCTAssertEqual(task.agent, "Trae CN")
        XCTAssertEqual(task.providerID, .traeCN)
        XCTAssertEqual(task.model, "unknown")
        XCTAssertEqual(task.tokenUsage, 0)
        XCTAssertTrue(task.summary.contains("task 6a1e900c"))
        XCTAssertTrue(task.summary.contains("不读取对话正文"))
    }
}
