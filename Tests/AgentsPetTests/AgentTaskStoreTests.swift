import XCTest
@testable import AgentsPet

@MainActor
final class AgentTaskStoreTests: XCTestCase {
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
    let providerName = "Mock"
    let tasks: [AgentTask]

    func fetchTasks() async -> [AgentTask] {
        tasks
    }
}

private struct MockRuntimeProvider: AgentRuntimeProvider {
    let providerName = "Mock Runtime"
    let runtimes: [AgentRuntime]

    func fetchRuntimes() async -> [AgentRuntime] {
        runtimes
    }
}
