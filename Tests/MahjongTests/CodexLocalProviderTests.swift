import XCTest
@testable import mahjong

final class CodexLocalProviderTests: XCTestCase {
    private var temporaryHome: URL!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("MahjongTests-\(UUID().uuidString)", isDirectory: true)
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
        let now = ISO8601DateFormatter().string(from: Date())
        let codexDirectory = temporaryHome.appendingPathComponent(".codex", isDirectory: true)
        let sessionsDirectory = codexDirectory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let index = """
        {"id":"\(sessionID)","thread_name":"Open source polish","updated_at":"\(now)"}
        """
        try index.write(
            to: codexDirectory.appendingPathComponent("session_index.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let session = """
        {"timestamp":"\(now)","payload":{"cwd":"\(temporaryHome.path)/mahjong","model":"gpt-test"}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"\(now)","payload":{"info":{"total_token_usage":{"total_tokens":42}}}}
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

    func testFetchTasksReadsSessionFilesWhenIndexIsStaleOrMissing() async throws {
        let sessionID = "22222222-3333-4444-5555-666666666666"
        let now = ISO8601DateFormatter().string(from: Date())
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("05", isDirectory: true)
            .appendingPathComponent("30", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let session = """
        {"timestamp":"\(now)","type":"session_meta","payload":{"id":"\(sessionID)","cwd":"\(temporaryHome.path)/mahjong","originator":"Codex Desktop"}}
        {"timestamp":"\(now)","type":"turn_context","payload":{"cwd":"\(temporaryHome.path)/mahjong","model":"gpt-live"}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"user_message","message":"Fix live detection\\n"}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"task_started"}}
        """
        let sessionURL = sessionsDirectory.appendingPathComponent("rollout-2026-05-30T15-00-00-\(sessionID).jsonl")
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let tasks = await CodexLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "codex:\(sessionID)")
        XCTAssertEqual(task.title, "Fix live detection")
        XCTAssertEqual(task.model, "gpt-live")
        XCTAssertEqual(task.status, .running)
        XCTAssertEqual(
            task.openURL?.resolvingSymlinksInPath().path,
            sessionURL.resolvingSymlinksInPath().path
        )
    }

    func testStaleStartedSessionIsNotRunningAndSkipsEnvironmentTitle() async throws {
        let sessionID = "33333333-4444-5555-6666-777777777777"
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let session = """
        {"timestamp":"2026-05-24T15:18:53Z","type":"session_meta","payload":{"id":"\(sessionID)","cwd":"\(temporaryHome.path)/agentspet"}}
        {"timestamp":"2026-05-24T15:18:53Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>\\n  <cwd>\(temporaryHome.path)</cwd>\\n</environment_context>"}]}}
        {"timestamp":"2026-05-24T15:18:54Z","type":"event_msg","payload":{"type":"user_message","message":"Add OpenClaw detection\\n"}}
        {"timestamp":"2026-05-24T15:44:29Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-05-24T15:48:44Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":425574}}}}
        """
        let sessionURL = sessionsDirectory.appendingPathComponent("rollout-\(sessionID).jsonl")
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let tasks = await CodexLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.title, "Add OpenClaw detection")
        XCTAssertNotEqual(task.status, .running)
        XCTAssertEqual(task.tokenUsage, 425574)
    }

    func testInterruptedSessionIsMarkedInterrupted() async throws {
        let sessionID = "44444444-5555-6666-7777-888888888888"
        let now = ISO8601DateFormatter().string(from: Date())
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let session = """
        {"timestamp":"\(now)","type":"session_meta","payload":{"id":"\(sessionID)","cwd":"\(temporaryHome.path)/mahjong"}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"user_message","message":"Run a long task\\n"}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}
        """
        let sessionURL = sessionsDirectory.appendingPathComponent("rollout-\(sessionID).jsonl")
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let tasks = await CodexLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.title, "Run a long task")
        XCTAssertEqual(task.status, .interrupted)
    }

    func testFetchUsageLimitsReadsLatestCodexRateLimits() async throws {
        let sessionID = "55555555-6666-7777-8888-999999999999"
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let session = """
        {"timestamp":"2026-06-04T09:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_name":"GPT-5 Codex","primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1780569000},"secondary":{"used_percent":25,"window_minutes":10080,"resets_at":1781155800}}}}
        {"timestamp":"2026-06-04T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_name":"GPT-5 Codex","primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1780570000},"secondary":{"used_percent":8,"window_minutes":10080,"resets_at":1781156800}}}}
        """
        let sessionURL = sessionsDirectory.appendingPathComponent("rollout-\(sessionID).jsonl")
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let fetchedSummary = await CodexLocalProvider(homeDirectory: temporaryHome).fetchUsageLimits()
        let summary = try XCTUnwrap(fetchedSummary.first)

        XCTAssertEqual(summary.limitName, "GPT-5 Codex")
        XCTAssertEqual(summary.primary.usedPercent, 2.0)
        XCTAssertEqual(summary.primary.remainingPercent, 98.0)
        XCTAssertEqual(summary.primary.windowMinutes, 300)
        XCTAssertEqual(summary.primary.resetsAt.timeIntervalSince1970, 1780570000, accuracy: 0.1)
        XCTAssertEqual(summary.secondary?.usedPercent, 8.0)
        XCTAssertEqual(summary.secondary?.remainingPercent, 92.0)
        XCTAssertEqual(summary.secondary?.windowMinutes, 10080)
    }

    func testFetchUsageLimitsPrefersLatestNonZeroRateLimitSnapshot() async throws {
        let sessionID = "66666666-7777-8888-9999-000000000000"
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let session = """
        {"timestamp":"2026-06-04T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":11.0,"window_minutes":300,"resets_at":1780570000},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1781156800}}}}
        {"timestamp":"2026-06-04T10:00:01Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1780571000},"secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1781157800}}}}
        """
        let sessionURL = sessionsDirectory.appendingPathComponent("rollout-\(sessionID).jsonl")
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let fetchedSummary = await CodexLocalProvider(homeDirectory: temporaryHome).fetchUsageLimits()
        let summary = try XCTUnwrap(fetchedSummary.first)

        XCTAssertEqual(summary.primary.usedPercent, 11.0)
        XCTAssertEqual(summary.primary.remainingPercent, 89.0)
        XCTAssertEqual(summary.secondary?.usedPercent, 10.0)
        XCTAssertEqual(summary.secondary?.remainingPercent, 90.0)
    }

    func testFetchUsageLimitsAcceptsZeroSnapshotAfterWindowReset() async throws {
        let sessionID = "77777777-8888-9999-0000-111111111111"
        let sessionsDirectory = temporaryHome
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let session = """
        {"timestamp":"2026-06-04T09:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":11.0,"window_minutes":300,"resets_at":1780563600},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1781156800}}}}
        {"timestamp":"2026-06-04T10:00:01Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_name":"GPT-5 Codex","primary":{"used_percent":0.0,"window_minutes":300,"resets_at":1780581600},"secondary":{"used_percent":0.0,"window_minutes":10080,"resets_at":1781161200}}}}
        """
        let sessionURL = sessionsDirectory.appendingPathComponent("rollout-\(sessionID).jsonl")
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        let fetchedSummary = await CodexLocalProvider(homeDirectory: temporaryHome).fetchUsageLimits()
        let summary = try XCTUnwrap(fetchedSummary.first)

        XCTAssertEqual(summary.primary.usedPercent, 0.0)
        XCTAssertEqual(summary.primary.remainingPercent, 100.0)
        XCTAssertEqual(summary.secondary?.usedPercent, 0.0)
        XCTAssertEqual(summary.secondary?.remainingPercent, 100.0)
    }
}
