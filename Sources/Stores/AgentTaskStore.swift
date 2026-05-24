import Foundation

@MainActor
final class AgentTaskStore: ObservableObject {
    @Published private(set) var tasks: [AgentTask]
    @Published private(set) var completionPulseID: UUID?

    private let providers: [AgentTaskProvider]
    private var providerTasks: [AgentTask] = []
    private var debugTasks: [AgentTask] = []
    private var nextMockIndex = 1
    private var refreshTask: Task<Void, Never>?
    private var knownCompletedTaskIDs: Set<String> = []

    init(providers: [AgentTaskProvider]? = nil) {
        self.providers = providers ?? [
            CodexLocalProvider(),
            ClaudeLocalProvider(),
            TerminalAgentProcessProvider(),
            DesktopAppPresenceProvider()
        ]

        debugTasks = []
        tasks = debugTasks
        knownCompletedTaskIDs = Set(tasks.filter { $0.status == .completed }.map(\.id))
    }

    deinit {
        refreshTask?.cancel()
    }

    var runningCount: Int {
        tasks.filter { $0.status == .running }.count
    }

    var isWorking: Bool {
        runningCount > 0
    }

    func tasks(for status: AgentTaskStatus) -> [AgentTask] {
        tasks
            .filter { $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func addMockRunningTask() {
        let task = AgentTask(
            id: "debug:mock-\(nextMockIndex)",
            title: "Agent 任务 \(nextMockIndex)",
            summary: "模拟一个新的并行 Agent 工作流",
            agent: nextMockIndex.isMultiple(of: 2) ? "Cursor" : "Codex",
            model: nextMockIndex.isMultiple(of: 2) ? "auto" : "gpt-5-codex",
            tokenUsage: Int.random(in: 2_000...15_000),
            status: .running
        )
        nextMockIndex += 1
        debugTasks.insert(task, at: 0)
        publishMergedTasks()
    }

    func completeOldestRunningTask() {
        guard let index = debugTasks.lastIndex(where: { $0.status == .running }) else {
            return
        }

        debugTasks[index].status = .completed
        debugTasks[index].summary = "任务已完成，等待用户查看结果"
        debugTasks[index].updatedAt = Date()
        publishMergedTasks()
        completionPulseID = UUID()
    }

    func archiveCompletedTasks() {
        for index in debugTasks.indices where debugTasks[index].status == .completed {
            debugTasks[index].status = .history
            debugTasks[index].updatedAt = Date()
        }
        publishMergedTasks()
    }

    func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshProviderTasks()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refreshProviderTasks()
        }
    }

    private func refreshProviderTasks() async {
        var fetchedTasks: [AgentTask] = []

        await withTaskGroup(of: [AgentTask].self) { group in
            for provider in providers {
                group.addTask {
                    await provider.fetchTasks()
                }
            }

            for await providerResult in group {
                fetchedTasks.append(contentsOf: providerResult)
            }
        }

        providerTasks = deduplicate(fetchedTasks)
        publishMergedTasks()
    }

    private func publishMergedTasks() {
        tasks = deduplicate(providerTasks + debugTasks)
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return statusSortIndex(lhs.status) < statusSortIndex(rhs.status)
                }
                return lhs.updatedAt > rhs.updatedAt
            }

        let completedTaskIDs = Set(tasks.filter { $0.status == .completed }.map(\.id))
        if !completedTaskIDs.subtracting(knownCompletedTaskIDs).isEmpty {
            completionPulseID = UUID()
        }
        knownCompletedTaskIDs = completedTaskIDs
    }

    private func deduplicate(_ tasks: [AgentTask]) -> [AgentTask] {
        var taskByID: [String: AgentTask] = [:]
        for task in tasks {
            if let existing = taskByID[task.id], existing.updatedAt > task.updatedAt {
                continue
            }
            taskByID[task.id] = task
        }
        return Array(taskByID.values)
    }

    private func statusSortIndex(_ status: AgentTaskStatus) -> Int {
        switch status {
        case .running: 0
        case .completed: 1
        case .history: 2
        }
    }
}
