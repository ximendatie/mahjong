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

    func testClaudeCLIFixtureMapsProviderIDAndStatus() async throws {
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
    }

    func testClaudeDesktopAuditRequestingMarksTaskRunning() async throws {
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        let sessionsDirectory = temporaryHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude-3p", isDirectory: true)
            .appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let metadataURL = sessionsDirectory.appendingPathComponent("local_running_fixture.json")
        let auditDirectory = sessionsDirectory.appendingPathComponent("local_running_fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: auditDirectory, withIntermediateDirectories: true)

        let metadata = """
        {"sessionId":"running-fixture","title":"Running desktop task","model":"claude-sonnet-test","lastActivityAt":\(nowMilliseconds),"isArchived":false}
        """
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)

        let audit = """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Summarize this."}]}}
        {"type":"system","status":"requesting"}
        {"type":"assistant","message":{"role":"assistant","type":"message","stop_reason":null,"usage":{"input_tokens":5,"output_tokens":0},"content":[]}}
        """
        try audit.write(
            to: auditDirectory.appendingPathComponent("audit.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let tasks = await ClaudeDesktopLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "claude-desktop:cowork:running-fixture")
        XCTAssertEqual(task.status, .running)
    }

    func testClaudeDesktopAuditResultMarksTaskCompleted() async throws {
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        let sessionsDirectory = temporaryHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude-3p", isDirectory: true)
            .appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let metadataURL = sessionsDirectory.appendingPathComponent("local_result_fixture.json")
        let auditDirectory = sessionsDirectory.appendingPathComponent("local_result_fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: auditDirectory, withIntermediateDirectories: true)

        let metadata = """
        {"sessionId":"result-fixture","title":"Completed desktop task","model":"claude-sonnet-test","lastActivityAt":\(nowMilliseconds),"isArchived":false}
        """
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)

        let audit = """
        {"type":"system","status":"requesting"}
        {"type":"assistant","message":{"role":"assistant","type":"message","stop_reason":null,"usage":{"input_tokens":5,"output_tokens":0},"content":[]}}
        {"type":"result","result":"Done"}
        """
        try audit.write(
            to: auditDirectory.appendingPathComponent("audit.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let tasks = await ClaudeDesktopLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "claude-desktop:cowork:result-fixture")
        XCTAssertEqual(task.status, .completed)
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
            insert into messages values ('hermes-fixture', 'user', \(nowSeconds - 25), 'Build status view', null);
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
    }

    func testHermesSQLiteFixtureMapsInterruptedEndReason() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: "/usr/bin/sqlite3"),
            "Hermes fixture test requires sqlite3."
        )

        let hermesDirectory = temporaryHome.appendingPathComponent(".hermes", isDirectory: true)
        try FileManager.default.createDirectory(at: hermesDirectory, withIntermediateDirectories: true)
        let databaseURL = hermesDirectory.appendingPathComponent("state.db")
        let nowSeconds = Int(Date().timeIntervalSince1970)

        try createHermesSchema(databaseURL: databaseURL)
        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            insert into sessions values (
                'hermes-interrupted',
                'cli',
                'gpt-hermes-test',
                \(nowSeconds - 30),
                \(nowSeconds),
                'interrupted',
                1,
                0,
                3,
                5,
                0,
                0,
                'Hermes interrupted task'
            );
            insert into messages values ('hermes-interrupted', 'user', \(nowSeconds - 25), 'Stop this task', null);
            """
        )

        let tasks = await HermesLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "hermes:hermes-interrupted")
        XCTAssertEqual(task.status, .interrupted)
    }

    func testOpenClawRunningTrajectoryMapsTaskRunning() async throws {
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let sessionURL = sessionsDirectory.appendingPathComponent("openclaw-running.jsonl")
        let trajectoryURL = sessionsDirectory.appendingPathComponent("openclaw-running.trajectory.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)

        let session = """
        {"type":"session","id":"openclaw-running","timestamp":"\(now)","cwd":"\(temporaryHome.path)/.openclaw"}
        {"type":"message","timestamp":"\(now)","message":{"role":"user","content":"[Sun 2026-05-31 14:18 GMT+8] 今天天气怎么样","timestamp":\(nowMilliseconds)}}
        {"type":"message","timestamp":"\(now)","message":{"role":"assistant","content":[{"type":"toolCall","name":"bash"}],"model":"gpt-5.5","usage":{"input":10,"output":2},"stopReason":"toolUse","timestamp":\(nowMilliseconds)}}
        """
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let trajectory = """
        {"type":"session.started","ts":"\(now)","sessionId":"openclaw-running","sessionKey":"agent:main:main","runId":"run-open","workspaceDir":"\(temporaryHome.path)/.openclaw/workspace","provider":"openai-codex","modelId":"gpt-5.5"}
        """
        try trajectory.write(to: trajectoryURL, atomically: true, encoding: .utf8)

        let tasks = await OpenClawLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "openclaw:openclaw-running")
        XCTAssertEqual(task.title, "今天天气怎么样")
        XCTAssertEqual(task.providerID, .openClaw)
        XCTAssertEqual(task.model, "gpt-5.5")
        XCTAssertEqual(task.tokenUsage, 12)
        XCTAssertEqual(task.status, .running)
    }

    func testOpenClawStaleUnendedTrajectoryDoesNotStayRunning() async throws {
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let sessionURL = sessionsDirectory.appendingPathComponent("openclaw-stale.jsonl")
        let trajectoryURL = sessionsDirectory.appendingPathComponent("openclaw-stale.trajectory.jsonl")
        let old = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -2 * 60 * 60))
        let oldMilliseconds = Int(Date(timeIntervalSinceNow: -2 * 60 * 60).timeIntervalSince1970 * 1000)

        let session = """
        {"type":"session","id":"openclaw-stale","timestamp":"\(old)","cwd":"\(temporaryHome.path)/.openclaw"}
        {"type":"message","timestamp":"\(old)","message":{"role":"user","content":"旧任务","timestamp":\(oldMilliseconds)}}
        {"type":"message","timestamp":"\(old)","message":{"role":"assistant","content":[{"type":"toolCall","name":"bash"}],"model":"qwen3.5:9b","usage":{"totalTokens":42},"stopReason":"toolUse","timestamp":\(oldMilliseconds)}}
        """
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let trajectory = """
        {"type":"session.started","ts":"\(old)","sessionId":"openclaw-stale","sessionKey":"agent:main:main","runId":"stale-run","workspaceDir":"\(temporaryHome.path)/.openclaw/workspace","provider":"ollama","modelId":"qwen3.5:9b"}
        """
        try trajectory.write(to: trajectoryURL, atomically: true, encoding: .utf8)

        let tasks = await OpenClawLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "openclaw:openclaw-stale")
        XCTAssertEqual(task.status, .completed)
    }

    func testOpenClawHeartbeatOnlySessionIsHidden() async throws {
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let sessionURL = sessionsDirectory.appendingPathComponent("openclaw-heartbeat.jsonl")
        let trajectoryURL = sessionsDirectory.appendingPathComponent("openclaw-heartbeat.trajectory.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)

        let session = """
        {"type":"session","id":"openclaw-heartbeat","timestamp":"\(now)","cwd":"\(temporaryHome.path)/.openclaw"}
        {"type":"message","timestamp":"\(now)","message":{"role":"user","content":"[OpenClaw heartbeat poll]","timestamp":\(nowMilliseconds)}}
        {"type":"message","timestamp":"\(now)","message":{"role":"assistant","content":[{"type":"text","text":"HEARTBEAT_OK"}],"model":"qwen3.5:9b","usage":{"totalTokens":4102},"stopReason":"stop","timestamp":\(nowMilliseconds)}}
        """
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let trajectory = """
        {"type":"session.started","ts":"\(now)","sessionId":"openclaw-heartbeat","sessionKey":"agent:main:main:heartbeat","runId":"heartbeat-run","workspaceDir":"\(temporaryHome.path)/.openclaw/workspace","provider":"ollama","modelId":"qwen3.5:9b","data":{"trigger":"heartbeat","messageProvider":"heartbeat"}}
        """
        try trajectory.write(to: trajectoryURL, atomically: true, encoding: .utf8)

        let tasks = await OpenClawLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        XCTAssertTrue(tasks.isEmpty)
    }

    func testOpenClawEndedTrajectoryMapsTaskCompleted() async throws {
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let sessionURL = sessionsDirectory.appendingPathComponent("openclaw-completed.jsonl")
        let trajectoryURL = sessionsDirectory.appendingPathComponent("openclaw-completed.trajectory.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)

        let session = """
        {"type":"session","id":"openclaw-completed","timestamp":"\(now)","cwd":"\(temporaryHome.path)/.openclaw"}
        {"type":"message","timestamp":"\(now)","message":{"role":"user","content":"总结天气","timestamp":\(nowMilliseconds)}}
        {"type":"message","timestamp":"\(now)","message":{"role":"assistant","content":[{"type":"text","text":"今天晴。"}],"model":"gpt-5.5","usage":{"totalTokens":32},"stopReason":"stop","timestamp":\(nowMilliseconds)}}
        {"type":"message","timestamp":"\(now)","message":{"role":"assistant","content":[{"type":"text","text":"今天晴。"}],"model":"delivery-mirror","usage":{"totalTokens":0},"stopReason":"stop","timestamp":\(nowMilliseconds)}}
        """
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let trajectory = """
        {"type":"session.started","ts":"\(now)","sessionId":"openclaw-completed","sessionKey":"agent:main:main","runId":"run-done","workspaceDir":"\(temporaryHome.path)/.openclaw/workspace","provider":"openai-codex","modelId":"gpt-5.5"}
        {"type":"session.ended","ts":"\(now)","sessionId":"openclaw-completed","sessionKey":"agent:main:main","runId":"run-done","workspaceDir":"\(temporaryHome.path)/.openclaw/workspace","provider":"openai-codex","modelId":"gpt-5.5","data":{"status":"success"}}
        """
        try trajectory.write(to: trajectoryURL, atomically: true, encoding: .utf8)

        let tasks = await OpenClawLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "openclaw:openclaw-completed")
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.model, "gpt-5.5")
        XCTAssertEqual(task.tokenUsage, 32)
    }

    func testOpenClawTitleStripsSenderMetadataEnvelope() async throws {
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let sessionURL = sessionsDirectory.appendingPathComponent("openclaw-metadata.jsonl")
        let trajectoryURL = sessionsDirectory.appendingPathComponent("openclaw-metadata.trajectory.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)

        let session = #"""
        {"type":"session","id":"openclaw-metadata","timestamp":"\#(now)","cwd":"\#(temporaryHome.path)/.openclaw"}
        {"type":"message","timestamp":"\#(now)","message":{"role":"user","content":"Sender (untrusted metadata):\n```json\n{\"label\":\"muzhi的Mac mini\"}\n```\n\n[Thu 2026-05-07 21:53 GMT+8] 我26年的体检报告存储位置是什么","timestamp":\#(nowMilliseconds)}}
        {"type":"message","timestamp":"\#(now)","message":{"role":"assistant","content":[{"type":"text","text":"已找到。"}],"model":"qwen3.5:9b","usage":{"totalTokens":42},"stopReason":"stop","timestamp":\#(nowMilliseconds)}}
        """#
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let trajectory = """
        {"type":"session.started","ts":"\(now)","sessionId":"openclaw-metadata","sessionKey":"agent:main:main","runId":"metadata-run","workspaceDir":"\(temporaryHome.path)/.openclaw/workspace","provider":"ollama","modelId":"qwen3.5:9b"}
        {"type":"session.ended","ts":"\(now)","sessionId":"openclaw-metadata","sessionKey":"agent:main:main","runId":"metadata-run","workspaceDir":"\(temporaryHome.path)/.openclaw/workspace","provider":"ollama","modelId":"qwen3.5:9b"}
        """
        try trajectory.write(to: trajectoryURL, atomically: true, encoding: .utf8)

        let tasks = await OpenClawLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.title, "我26年的体检报告存储位置是什么")
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

    private func createHermesSchema(databaseURL: URL) throws {
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
            """
        )
    }
}
