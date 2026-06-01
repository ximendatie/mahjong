import XCTest
@testable import mahjong

@MainActor
final class AgentTaskStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "local.mahjong.futureTasks")
        UserDefaults.standard.removeObject(forKey: "local.mahjong.providerSettings")
        UserDefaults.standard.removeObject(forKey: "local.mahjong.privacyMode")
        UserDefaults.standard.removeObject(forKey: "local.mahjong.menuBarMode")
        UserDefaults.standard.removeObject(forKey: "local.mahjong.dockIconMode")
        UserDefaults.standard.removeObject(forKey: "local.mahjong.readCompletedTaskIDs")
    }

    func testRefreshDeduplicatesTasksAndRuntimes() async throws {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let tasks = [
            AgentTask(
                id: "same",
                title: "Older",
                summary: "old",
                agent: "Test",
                model: "model",
                tokenUsage: 1,
                status: .running,
                updatedAt: older
            ),
            AgentTask(
                id: "same",
                title: "Newer",
                summary: "new",
                agent: "Test",
                model: "model",
                tokenUsage: 2,
                status: .completed,
                updatedAt: newer
            )
        ]
        let runtimes = [
            AgentRuntime(
                id: "runtime",
                name: "Codex CLI",
                provider: "Codex",
                kind: .terminal,
                summary: "one",
                processCount: 1,
                updatedAt: older
            ),
            AgentRuntime(
                id: "runtime",
                name: "Codex CLI",
                provider: "Codex",
                kind: .terminal,
                summary: "two",
                processCount: 2,
                updatedAt: newer
            )
        ]
        let store = AgentTaskStore(
            providers: [MockTaskProvider(tasks: tasks)],
            runtimeProviders: [MockRuntimeProvider(runtimes: runtimes)]
        )

        store.refreshNow()
        try await waitUntil { store.tasks.count == 1 && store.runtimes.count == 1 }

        XCTAssertEqual(store.tasks.first?.title, "Newer")
        XCTAssertEqual(store.runtimes.first?.processCount, 3)
        XCTAssertEqual(store.runtimes.first?.updatedAt, newer)
    }

    func testCompleteAndArchiveApplyLocalOverrides() async throws {
        let store = AgentTaskStore(
            providers: [
                MockTaskProvider(tasks: [
                    AgentTask(
                        id: "task",
                        title: "Running task",
                        summary: "summary",
                        agent: "Test",
                        model: "model",
                        tokenUsage: 0,
                        status: .running,
                        updatedAt: Date()
                    )
                ])
            ],
            runtimeProviders: []
        )

        store.refreshNow()
        try await waitUntil { store.task(id: "task") != nil }

        store.completeTask(id: "task")
        XCTAssertEqual(store.task(id: "task")?.status, .completed)
        XCTAssertNotNil(store.completionPulseID)
        XCTAssertEqual(store.unreadCompletedCount, 1)

        store.archiveTask(id: "task")
        XCTAssertEqual(store.task(id: "task")?.status, .history)
    }

    func testCompletedTasksCanBeMarkedRead() async throws {
        let store = AgentTaskStore(
            providers: [
                MockTaskProvider(tasks: [
                    AgentTask(
                        id: "task",
                        title: "Running task",
                        summary: "summary",
                        agent: "Test",
                        model: "model",
                        tokenUsage: 0,
                        status: .running,
                        updatedAt: Date()
                    )
                ])
            ],
            runtimeProviders: []
        )

        store.refreshNow()
        try await waitUntil { store.task(id: "task") != nil }

        store.completeTask(id: "task")
        XCTAssertTrue(store.hasUnreadCompletedTasks)
        XCTAssertEqual(store.unreadCompletedCount, 1)

        store.markCompletedTasksRead()
        XCTAssertFalse(store.hasUnreadCompletedTasks)
        XCTAssertEqual(store.unreadCompletedCount, 0)
    }

    func testCompletedReadStatePersistsAcrossReloads() async throws {
        let completedTask = AgentTask(
            id: "task",
            title: "Completed task",
            summary: "summary",
            agent: "Test",
            model: "model",
            tokenUsage: 0,
            status: .completed,
            updatedAt: Date()
        )
        let store = AgentTaskStore(
            providers: [MockTaskProvider(tasks: [completedTask])],
            runtimeProviders: []
        )

        store.refreshNow()
        try await waitUntil { store.task(id: "task") != nil }
        XCTAssertFalse(store.hasUnreadCompletedTasks)

        let reloadedStore = AgentTaskStore(
            providers: [MockTaskProvider(tasks: [completedTask])],
            runtimeProviders: []
        )

        reloadedStore.refreshNow()
        try await waitUntil { reloadedStore.task(id: "task") != nil }
        XCTAssertFalse(reloadedStore.hasUnreadCompletedTasks)
        XCTAssertEqual(reloadedStore.unreadCompletedCount, 0)
    }

    func testDisabledProviderIsSkippedAndReported() async throws {
        let store = AgentTaskStore(
            providers: [
                MockTaskProvider(providerName: "Codex", tasks: [
                    AgentTask(
                        id: "codex-task",
                        title: "Running task",
                        summary: "summary",
                        agent: "Codex",
                        model: "model",
                        tokenUsage: 0,
                        status: .running,
                        updatedAt: Date()
                    )
                ])
            ],
            runtimeProviders: []
        )

        store.setProviderEnabled(id: "codex", isEnabled: false)
        try await waitUntil { store.diagnostics.first { $0.id == "codex" }?.status == .disabled }

        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testChatGPTRunningWithoutAccessibilityReportsActionableDiagnostic() async throws {
        let store = AgentTaskStore(
            providers: [],
            runtimeProviders: [
                MockRuntimeProvider(
                    providerID: .desktopApps,
                    providerName: "Desktop Apps",
                    runtimes: [
                        AgentRuntime(
                            id: "desktop:chatgpt",
                            name: "ChatGPT Desktop",
                            provider: "OpenAI",
                            providerID: .desktopApps,
                            kind: .desktopApp,
                            summary: "running",
                            bundleIdentifier: "com.openai.chat"
                        )
                    ]
                )
            ],
            isChatGPTAccessibilityTrusted: { false }
        )

        store.refreshNow()
        try await waitUntil {
            store.diagnostics.first { $0.id == AgentProviderID.chatGPT.rawValue }?.status == .failed
        }

        let diagnostic = try XCTUnwrap(store.diagnostics.first { $0.id == AgentProviderID.chatGPT.rawValue })
        XCTAssertTrue(diagnostic.message.contains("Accessibility"))
        XCTAssertTrue(diagnostic.message.contains("System Settings"))
        XCTAssertTrue(diagnostic.message.contains("Conversation text is still not read"))
    }

    func testFutureTasksAreSimpleLocalItems() {
        let store = AgentTaskStore(providers: [], runtimeProviders: [])

        store.createFutureTask(title: "整理第三阶段", note: "先做轻量记录事项")

        XCTAssertEqual(store.futureTasks.count, 1)
        let task = store.futureTasks[0]
        XCTAssertEqual(task.title, "整理第三阶段")
        XCTAssertEqual(task.note, "先做轻量记录事项")
        XCTAssertFalse(task.isCompleted)

        store.setFutureTaskCompleted(id: task.id, isCompleted: true)
        XCTAssertTrue(store.futureTasks[0].isCompleted)
    }

    func testFutureTaskTitleFallsBackToFirstNoteLine() {
        let store = AgentTaskStore(providers: [], runtimeProviders: [])

        store.createFutureTask(title: "", note: "记录一个未来想法\n第二行细节")

        XCTAssertEqual(store.futureTasks.first?.title, "记录一个未来想法")
    }

    func testMenuBarModeDefaultsOnAndPersists() {
        let store = AgentTaskStore(providers: [], runtimeProviders: [])

        XCTAssertTrue(store.isMenuBarEnabled)

        store.setMenuBarEnabled(false)

        let reloadedStore = AgentTaskStore(providers: [], runtimeProviders: [])
        XCTAssertFalse(reloadedStore.isMenuBarEnabled)
    }

    func testDockIconModeDefaultsOnAndPersists() {
        let store = AgentTaskStore(providers: [], runtimeProviders: [])

        XCTAssertTrue(store.isDockIconEnabled)

        store.setDockIconEnabled(false)

        let reloadedStore = AgentTaskStore(providers: [], runtimeProviders: [])
        XCTAssertFalse(reloadedStore.isDockIconEnabled)
    }

    func testTokenUsageSummariesGroupByAgentAndFilterDateRange() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let today = now.addingTimeInterval(-60 * 60)
        let lastWeek = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let old = now.addingTimeInterval(-45 * 24 * 60 * 60)
        let store = AgentTaskStore(
            providers: [
                MockTaskProvider(tasks: [
                    AgentTask(
                        id: "codex-today",
                        title: "Today",
                        summary: "summary",
                        agent: "Codex",
                        providerID: .codex,
                        model: "model",
                        tokenUsage: 100,
                        status: .completed,
                        updatedAt: today
                    ),
                    AgentTask(
                        id: "codex-week",
                        title: "Week",
                        summary: "summary",
                        agent: "Codex",
                        providerID: .codex,
                        model: "model",
                        tokenUsage: 30,
                        status: .history,
                        updatedAt: lastWeek
                    ),
                    AgentTask(
                        id: "claude-old",
                        title: "Old",
                        summary: "summary",
                        agent: "Claude",
                        providerID: .claudeCLI,
                        model: "model",
                        tokenUsage: 300,
                        status: .history,
                        updatedAt: old
                    )
                ])
            ],
            runtimeProviders: []
        )

        store.refreshNow()
        try await waitUntil { store.tasks.count == 3 }

        let all = store.tokenUsageSummaries(for: .all, now: now, calendar: calendar)
        XCTAssertEqual(all.map(\.agent), ["Claude", "Codex"])
        XCTAssertEqual(all.first?.totalTokens, 300)
        XCTAssertEqual(all.last?.totalTokens, 130)
        XCTAssertEqual(all.last?.taskCount, 2)

        let lastMonth = store.tokenUsageSummaries(for: .lastMonth, now: now, calendar: calendar)
        XCTAssertEqual(lastMonth.map(\.agent), ["Codex"])
        XCTAssertEqual(lastMonth.first?.totalTokens, 130)

        let todayOnly = store.tokenUsageSummaries(for: .today, now: now, calendar: calendar)
        XCTAssertEqual(todayOnly.map(\.agent), ["Codex"])
        XCTAssertEqual(todayOnly.first?.totalTokens, 100)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private struct MockTaskProvider: AgentTaskProvider {
    var providerID = AgentProviderID.codex
    var providerName = "Codex"
    let tasks: [AgentTask]

    func fetchTasks() async -> [AgentTask] {
        tasks
    }
}

private struct MockRuntimeProvider: AgentRuntimeProvider {
    var providerID = AgentProviderID.terminalAgents
    var providerName = "Terminal Agents"
    let runtimes: [AgentRuntime]

    func fetchRuntimes() async -> [AgentRuntime] {
        runtimes
    }
}
