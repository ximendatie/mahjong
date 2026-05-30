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

        store.archiveTask(id: "task")
        XCTAssertEqual(store.task(id: "task")?.status, .history)
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
    let providerID = AgentProviderID.terminalAgents
    let providerName = "Terminal Agents"
    let runtimes: [AgentRuntime]

    func fetchRuntimes() async -> [AgentRuntime] {
        runtimes
    }
}
