import Foundation

@MainActor
final class AgentTaskStore: ObservableObject {
    @Published private(set) var tasks: [AgentTask]
    @Published private(set) var runtimes: [AgentRuntime]
    @Published private(set) var futureTasks: [FutureAgentTask]
    @Published private(set) var completionPulseID: UUID?

    private static let futureTasksStorageKey = "local.agentspet.futureTasks"

    private let providers: [AgentTaskProvider]
    private let runtimeProviders: [AgentRuntimeProvider]
    private var providerTasks: [AgentTask] = []
    private var localStatusOverrides: [String: AgentTaskStatus] = [:]
    private var localUpdatedAtOverrides: [String: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var knownCompletedTaskIDs: Set<String> = []

    init(
        providers: [AgentTaskProvider]? = nil,
        runtimeProviders: [AgentRuntimeProvider]? = nil
    ) {
        self.providers = providers ?? [
            CodexLocalProvider(),
            ClaudeLocalProvider(),
            ClaudeDesktopLocalProvider(),
            HermesLocalProvider()
        ]
        self.runtimeProviders = runtimeProviders ?? [
            TerminalAgentRuntimeProvider(),
            DesktopAppRuntimeProvider()
        ]

        tasks = []
        runtimes = []
        futureTasks = Self.loadFutureTasks()
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

    var runningAgentCount: Int {
        runtimes.count
    }

    func tasks(for status: AgentTaskStatus) -> [AgentTask] {
        tasks
            .filter { $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func task(id: String?) -> AgentTask? {
        guard let id else {
            return nil
        }
        return tasks.first { $0.id == id }
    }

    func futureTasks(for agent: FutureAgent) -> [FutureAgentTask] {
        futureTasks
            .filter { $0.agent == agent }
            .sorted { lhs, rhs in
                if lhs.scheduledAt != rhs.scheduledAt {
                    return lhs.scheduledAt < rhs.scheduledAt
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func createFutureTask(
        title: String,
        prompt: String,
        agent: FutureAgent,
        modelHint: String,
        scheduledAt: Date
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedPrompt.isEmpty else {
            return
        }

        let task = FutureAgentTask(
            title: trimmedTitle,
            prompt: trimmedPrompt,
            agent: agent,
            modelHint: modelHint.trimmingCharacters(in: .whitespacesAndNewlines),
            scheduledAt: scheduledAt
        )

        futureTasks.append(task)
        persistFutureTasks()
    }

    func deleteFutureTask(id: FutureAgentTask.ID) {
        futureTasks.removeAll { $0.id == id }
        persistFutureTasks()
    }

    func completeTask(id: String?) {
        guard let id, let task = task(id: id), task.status == .running else {
            return
        }

        localStatusOverrides[id] = .completed
        localUpdatedAtOverrides[id] = Date()

        publishMergedTasks()
        completionPulseID = UUID()
    }

    func archiveTask(id: String?) {
        guard let id, let task = task(id: id), task.status != .running else {
            return
        }

        localStatusOverrides[id] = .history
        localUpdatedAtOverrides[id] = Date()

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
        var fetchedRuntimes: [AgentRuntime] = []

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

        await withTaskGroup(of: [AgentRuntime].self) { group in
            for provider in runtimeProviders {
                group.addTask {
                    await provider.fetchRuntimes()
                }
            }

            for await providerResult in group {
                fetchedRuntimes.append(contentsOf: providerResult)
            }
        }

        providerTasks = deduplicate(fetchedTasks)
        runtimes = deduplicate(fetchedRuntimes)
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind.title < rhs.kind.title
                }
                return lhs.name < rhs.name
            }
        publishMergedTasks()
    }

    private func publishMergedTasks() {
        tasks = deduplicate(archiveCompletedBeforeToday(applyLocalOverrides(to: providerTasks)))
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

    private func applyLocalOverrides(to tasks: [AgentTask]) -> [AgentTask] {
        tasks.map { task in
            var updatedTask = task
            if let status = localStatusOverrides[task.id] {
                updatedTask.status = status
            }
            if let updatedAt = localUpdatedAtOverrides[task.id] {
                updatedTask.updatedAt = updatedAt
            }
            return updatedTask
        }
    }

    private func archiveCompletedBeforeToday(_ tasks: [AgentTask]) -> [AgentTask] {
        let calendar = Calendar.current
        return tasks.map { task in
            guard task.status == .completed, !calendar.isDateInToday(task.updatedAt) else {
                return task
            }

            var archivedTask = task
            archivedTask.status = .history
            return archivedTask
        }
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

    private func deduplicate(_ runtimes: [AgentRuntime]) -> [AgentRuntime] {
        var runtimeByID: [String: AgentRuntime] = [:]
        for runtime in runtimes {
            if let existing = runtimeByID[runtime.id] {
                var merged = existing
                merged.processCount += runtime.processCount
                merged.updatedAt = max(existing.updatedAt, runtime.updatedAt)
                runtimeByID[runtime.id] = merged
            } else {
                runtimeByID[runtime.id] = runtime
            }
        }
        return Array(runtimeByID.values)
    }

    private func statusSortIndex(_ status: AgentTaskStatus) -> Int {
        switch status {
        case .running: 0
        case .completed: 1
        case .history: 2
        }
    }

    private static func loadFutureTasks() -> [FutureAgentTask] {
        guard let data = UserDefaults.standard.data(forKey: futureTasksStorageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([FutureAgentTask].self, from: data)
        } catch {
            return []
        }
    }

    private func persistFutureTasks() {
        do {
            let data = try JSONEncoder().encode(futureTasks)
            UserDefaults.standard.set(data, forKey: Self.futureTasksStorageKey)
        } catch {
            assertionFailure("Failed to persist future tasks: \(error)")
        }
    }
}
