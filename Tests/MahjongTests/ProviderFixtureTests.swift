import XCTest
@testable import mahjong

final class ProviderFixtureTests: XCTestCase {
    private var temporaryHome: URL!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("MahjongProviderFixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryHome {
            try? FileManager.default.removeItem(at: temporaryHome)
        }
        temporaryHome = nil
    }

    func testClaudeCLIFixtureMapsProviderIDAndConfidence() async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let projectDirectory = temporaryHome
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-Users-muzhi-Documents-mahjong", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        let fixture = """
        {"sessionId":"claude-fixture","timestamp":"\(now)","cwd":"\(temporaryHome.path)/mahjong","customTitle":"Claude fixture task","type":"user","message":{"model":"claude-opus-test","usage":{"input_tokens":10,"output_tokens":3,"cache_creation_input_tokens":2,"cache_read_input_tokens":1}}}
        """
        try fixture.write(
            to: projectDirectory.appendingPathComponent("claude-fixture.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let tasks = await ClaudeLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "claude:claude-fixture")
        XCTAssertEqual(task.title, "Claude fixture task")
        XCTAssertEqual(task.providerID, .claudeCLI)
        XCTAssertEqual(task.model, "claude-opus-test")
        XCTAssertEqual(task.tokenUsage, 16)
        XCTAssertEqual(task.status, .running)
        XCTAssertEqual(task.confidence, .inferred)
    }

    func testClaudeDesktopFixtureMapsMetadataAndAuditUsage() async throws {
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        let sessionsDirectory = temporaryHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude-3p", isDirectory: true)
            .appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let metadataURL = sessionsDirectory.appendingPathComponent("local_desktop_fixture.json")
        let auditDirectory = sessionsDirectory.appendingPathComponent("local_desktop_fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: auditDirectory, withIntermediateDirectories: true)

        let metadata = """
        {"sessionId":"desktop-fixture","title":"Desktop fixture task","originCwd":"\(temporaryHome.path)/mahjong","model":"claude-sonnet-test","lastActivityAt":\(nowMilliseconds),"isArchived":false,"isAgentCompleted":true}
        """
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)

        let audit = """
        {"message":{"usage":{"input_tokens":5,"output_tokens":7,"cache_creation_input_tokens":11,"cache_read_input_tokens":13}}}
        """
        try audit.write(
            to: auditDirectory.appendingPathComponent("audit.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let tasks = await ClaudeDesktopLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "claude-desktop:cowork:desktop-fixture")
        XCTAssertEqual(task.title, "Desktop fixture task")
        XCTAssertEqual(task.providerID, .claudeDesktop)
        XCTAssertEqual(task.model, "claude-sonnet-test")
        XCTAssertEqual(task.tokenUsage, 36)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.confidence, .inferred)
    }

    func testHermesSQLiteFixtureMapsProviderIDAndConfirmedCompletion() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: "/usr/bin/sqlite3"),
            "Hermes fixture test requires sqlite3."
        )

        let hermesDirectory = temporaryHome.appendingPathComponent(".hermes", isDirectory: true)
        try FileManager.default.createDirectory(at: hermesDirectory, withIntermediateDirectories: true)
        let databaseURL = hermesDirectory.appendingPathComponent("state.db")
        let nowSeconds = Int(Date().timeIntervalSince1970)

        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            create table sessions (
                id text primary key,
                source text,
                model text,
                started_at integer,
                ended_at integer,
                end_reason text,
                message_count integer,
                tool_call_count integer,
                input_tokens integer,
                output_tokens integer,
                cache_read_tokens integer,
                cache_write_tokens integer,
                title text
            );
            create table messages (
                session_id text,
                role text,
                timestamp integer,
                content text,
                finish_reason text
            );
            insert into sessions values (
                'hermes-fixture',
                'cli',
                'gpt-hermes-test',
                \(nowSeconds - 30),
                \(nowSeconds),
                'stop',
                2,
                1,
                17,
                19,
                23,
                29,
                'Hermes fixture task'
            );
            insert into messages values ('hermes-fixture', 'user', \(nowSeconds - 25), 'Build status confidence', null);
            insert into messages values ('hermes-fixture', 'assistant', \(nowSeconds - 1), 'Done', 'stop');
            """
        )

        let tasks = await HermesLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "hermes:hermes-fixture")
        XCTAssertEqual(task.title, "Hermes fixture task")
        XCTAssertEqual(task.providerID, .hermes)
        XCTAssertEqual(task.model, "gpt-hermes-test")
        XCTAssertEqual(task.tokenUsage, 88)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.confidence, .confirmed)
    }

    private func runSQLite(databaseURL: URL, sql: String) throws {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("sqlite3 failed: \(error)")
        }
    }
}
