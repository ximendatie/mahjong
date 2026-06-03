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

    func testSessionLookupLogLinesAreIgnored() {
        let getSessionsLine = """
        2026-06-03T21:34:08.225465+08:00  INFO process_ipc_request:route:get_sessions:get_latest_session_status:get_latest_session_status_with_db_source: ai_agent::infrastructure::dal::connection: [DB] new connection connected project_id=67c6b20b6898bca0a088857a session_id=6a1e50468662d364fffb92d7 session_id=6a1e50468662d364fffb92d7
        """
        let getMessagesLine = """
        2026-06-03T21:34:08.657120+08:00  INFO process_ipc_request:route: ai_agent::handler::chat: [ChatHandler::router] starting, method: get_messages, session_id: Some("6a1fe8798662d364fffb95a8")
        """
        let cacheBuildLine = """
        2026-06-03T21:34:08.660895+08:00  INFO ai_agent::domain::chat::server_service: [build_server_history_ids_cache] START: session_id=6a1fe8798662d364fffb95a8
        """

        XCTAssertNil(TraeCNLocalProvider.event(from: getSessionsLine[...]))
        XCTAssertNil(TraeCNLocalProvider.event(from: getMessagesLine[...]))
        XCTAssertNil(TraeCNLocalProvider.event(from: cacheBuildLine[...]))
    }

    func testDoChatWithoutTaskIDIsIgnored() {
        let line = """
        2026-06-02T16:10:53.123430+08:00  INFO process_ipc_request:route:chat:do_chat: session_id=6a1e57868662d364fffb938d message_id=6a1e900c8662d364fffb944b
        """

        XCTAssertNil(TraeCNLocalProvider.event(from: line[...]))
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

    func testFetchTasksIgnoresSessionLookupMetadata() async throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mahjong-trae-lookup-tests-\(UUID().uuidString)", isDirectory: true)
        let logDirectory = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Trae CN", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("20260603T213407", isDirectory: true)
            .appendingPathComponent("Modular", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logURL = logDirectory.appendingPathComponent("ai-agent_0_1780493647156_stdout.log")
        try """
        \(timestamp)  INFO process_ipc_request:route:get_sessions:get_latest_session_status:get_latest_session_status_with_db_source: ai_agent::infrastructure::dal::connection: [DB] new connection connected project_id=67c6b20b6898bca0a088857a session_id=6a1e50468662d364fffb92d7 session_id=6a1e50468662d364fffb92d7
        \(timestamp)  INFO process_ipc_request:route: ai_agent::handler::chat: [ChatHandler::router] starting, method: get_messages, session_id: Some("6a1fe8798662d364fffb95a8")
        \(timestamp)  INFO ai_agent::domain::chat::server_service: [build_server_history_ids_cache] START: session_id=6a1fe8798662d364fffb95a8
        """.write(to: logURL, atomically: true, encoding: .utf8)

        let provider = TraeCNLocalProvider(homeDirectory: home)
        let tasks = await provider.fetchTasks()

        XCTAssertTrue(tasks.isEmpty)
    }
}
