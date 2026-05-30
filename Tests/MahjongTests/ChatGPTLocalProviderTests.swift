import XCTest
@testable import mahjong

final class ChatGPTLocalProviderTests: XCTestCase {
    private var temporaryHome: URL!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("MahjongChatGPTTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryHome {
            try? FileManager.default.removeItem(at: temporaryHome)
        }
        temporaryHome = nil
    }

    func testRecentConversationCacheCreatesCompletedTask() async throws {
        try writeConversationCache(modifiedAt: Date())
        let provider = ChatGPTLocalProvider(
            homeDirectory: temporaryHome,
            runningAppSnapshot: { nil },
            isGeneratingResponse: { _ in false },
            isAccessibilityTrusted: { false }
        )

        let tasks = await provider.fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, "chatgpt:desktop")
        XCTAssertEqual(task.title, "ChatGPT Desktop")
        XCTAssertEqual(task.agent, "ChatGPT")
        XCTAssertEqual(task.providerID, .chatGPT)
        XCTAssertEqual(task.status, .completed)
    }

    func testRunningChatGPTWithAccessibilityStopControlCreatesRunningTask() async throws {
        try writeConversationCache(modifiedAt: Date().addingTimeInterval(-60 * 60))
        let provider = ChatGPTLocalProvider(
            homeDirectory: temporaryHome,
            runningAppSnapshot: {
                ChatGPTRunningApp(
                    pid: 123,
                    bundleIdentifier: "com.openai.chat",
                    localizedName: "ChatGPT"
                )
            },
            isGeneratingResponse: { pid in pid == 123 },
            isAccessibilityTrusted: { true }
        )

        let tasks = await provider.fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.status, .running)
        XCTAssertEqual(task.summary, "ChatGPT Desktop 正在生成响应")
    }

    func testRunningChatGPTWithoutConversationActivityDoesNotCreateTask() async throws {
        let provider = ChatGPTLocalProvider(
            homeDirectory: temporaryHome,
            runningAppSnapshot: {
                ChatGPTRunningApp(
                    pid: 123,
                    bundleIdentifier: "com.openai.chat",
                    localizedName: "ChatGPT"
                )
            },
            isGeneratingResponse: { _ in true },
            isAccessibilityTrusted: { false }
        )

        let tasks = await provider.fetchTasks()

        XCTAssertTrue(tasks.isEmpty)
    }

    func testRunningChatGPTWithRecentConversationCreatesCompletedTask() async throws {
        try writeConversationCache(modifiedAt: Date())
        let provider = ChatGPTLocalProvider(
            homeDirectory: temporaryHome,
            runningAppSnapshot: {
                ChatGPTRunningApp(
                    pid: 123,
                    bundleIdentifier: "com.openai.chat",
                    localizedName: "ChatGPT"
                )
            },
            isGeneratingResponse: { _ in false },
            isAccessibilityTrusted: { false }
        )

        let tasks = await provider.fetchTasks()

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.summary, "ChatGPT Desktop 已运行；最近有本地活动")
    }

    private func writeConversationCache(modifiedAt: Date) throws {
        let directory = temporaryHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.openai.chat", isDirectory: true)
            .appendingPathComponent("conversations-v3-test", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("conversation.data")
        try Data([0x01, 0x02, 0x03]).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: fileURL.path)
    }
}
