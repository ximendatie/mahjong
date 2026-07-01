import XCTest
@testable import mahjong

final class CursorLocalProviderTests: XCTestCase {
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

    func testFetchTasksReadsCursorComposerSessionMetadata() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: "/usr/bin/sqlite3"),
            "Cursor fixture test requires sqlite3."
        )

        let databaseURL = try createCursorStateDatabase()
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)

        try insertCursorComposer(
            databaseURL: databaseURL,
            id: "11111111-2222-3333-4444-555555555555",
            json: """
            {
              "composerId": "11111111-2222-3333-4444-555555555555",
              "name": "Refine checkout agent",
              "createdAt": \(nowMilliseconds - 120_000),
              "lastUpdatedAt": \(nowMilliseconds - 30_000),
              "status": "completed",
              "isAgentic": true,
              "modelConfig": { "modelName": "cursor-model-test" },
              "usageData": { "totalTokens": 321 }
            }
            """
        )
        try insertCursorComposer(
            databaseURL: databaseURL,
            id: "empty-draft",
            json: """
            {
              "composerId": "empty-draft",
              "name": "",
              "createdAt": \(nowMilliseconds),
              "lastUpdatedAt": \(nowMilliseconds),
              "status": "none",
              "isAgentic": true
            }
            """
        )

        let tasks = await CursorLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "cursor:11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(task.title, "Refine checkout agent")
        XCTAssertEqual(task.agent, "Cursor")
        XCTAssertEqual(task.providerID, .cursor)
        XCTAssertEqual(task.model, "cursor-model-test")
        XCTAssertEqual(task.tokenUsage, 321)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(
            task.openURL?.resolvingSymlinksInPath().path,
            databaseURL.resolvingSymlinksInPath().path
        )
    }

    func testAbortedComposerSessionIsMarkedInterrupted() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: "/usr/bin/sqlite3"),
            "Cursor fixture test requires sqlite3."
        )

        let databaseURL = try createCursorStateDatabase()
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)

        try insertCursorComposer(
            databaseURL: databaseURL,
            id: "aborted-session",
            json: """
            {
              "composerId": "aborted-session",
              "name": "Stop bad edit",
              "createdAt": \(nowMilliseconds - 60_000),
              "lastUpdatedAt": \(nowMilliseconds - 10_000),
              "status": "aborted",
              "isAgentic": true
            }
            """
        )

        let tasks = await CursorLocalProvider(homeDirectory: temporaryHome).fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "cursor:aborted-session")
        XCTAssertEqual(task.status, .interrupted)
    }

    private func createCursorStateDatabase() throws -> URL {
        let databaseDirectory = temporaryHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Cursor", isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)

        let databaseURL = databaseDirectory.appendingPathComponent("state.vscdb")
        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            create table cursorDiskKV (
                key text primary key,
                value blob
            );
            """
        )
        return databaseURL
    }

    private func insertCursorComposer(databaseURL: URL, id: String, json: String) throws {
        let escapedJSON = json.replacingOccurrences(of: "'", with: "''")
        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            insert into cursorDiskKV values ('composerData:\(id)', '\(escapedJSON)');
            """
        )
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
