import Foundation

@MainActor
final class AgentTaskStore: ObservableObject {
    @Published private(set) var tasks: [AgentTask]
    @Published private(set) var runtimes: [AgentRuntime]
    @Published private(set) var futureTasks: [FutureAgentTask]
    @Published private(set) var completionPulseID: UUID?
    @Published private(set) var providerSettings: [AgentProviderSetting]
    @Published private(set) var diagnostics: [ProviderDiagnostic]
    @Published private(set) var isPrivacyModeEnabled: Bool

    private static let futureTasksStorageKey = "local.mahjong.futureTasks"
    private static let legacyFutureTasksStorageKey = "local.agentspet.futureTasks"
    private static let providerSettingsStorageKey = "local.mahjong.providerSettings"
    private static let privacyModeStorageKey = "local.mahjong.privacyMode"

    private let descriptors: [AgentProviderDescriptor]
    private let providers: [AgentTaskProvider]
    private let runtimeProviders: [AgentRuntimeProvider]
    private var providerTasks: [AgentTask] = []
    private var localStatusOverrides: [String: AgentTaskStatus] = [:]
    private var localUpdatedAtOverrides: [String: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var knownCompletedTaskIDs: Set<String> = []

    init(
        descriptors: [AgentProviderDescriptor]? = nil,
        providers: [AgentTaskProvider]? = nil,
        runtimeProviders: [AgentRuntimeProvider]? = nil
    ) {
        self.descriptors = descriptors ?? AgentProviderDescriptor.defaults()
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
        let loadedProviderSettings = Self.loadProviderSettings(descriptors: self.descriptors)
        providerSettings = loadedProviderSettings
        diagnostics = initialDiagnostics(for: loadedProviderSettings, descriptors: self.descriptors)
        isPrivacyModeEnabled = UserDefaults.standard.bool(forKey: Self.privacyModeStorageKey)
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

    func setProviderEnabled(id: String, isEnabled: Bool) {
        guard let index = providerSettings.firstIndex(where: { $0.id == id }) else {
            return
        }

        providerSettings[index].isEnabled = isEnabled
        persistProviderSettings()
        refreshNow()
    }

    func setPrivacyModeEnabled(_ isEnabled: Bool) {
        isPrivacyModeEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.privacyModeStorageKey)
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
        let enabledIDs = Set(providerSettings.filter(\.isEnabled).map(\.id))
        var taskFetches: [ProviderTaskFetch] = []
        var runtimeFetches: [ProviderRuntimeFetch] = []

        await withTaskGroup(of: ProviderTaskFetch.self) { group in
            for provider in providers {
                let id = provider.providerID.rawValue
                guard enabledIDs.contains(id) else {
                    continue
                }
                group.addTask {
                    ProviderTaskFetch(
                        id: id,
                        providerName: provider.providerName,
                        tasks: await provider.fetchTasks()
                    )
                }
            }

            for await fetch in group {
                taskFetches.append(fetch)
            }
        }

        await withTaskGroup(of: ProviderRuntimeFetch.self) { group in
            for provider in runtimeProviders {
                let id = provider.providerID.rawValue
                guard enabledIDs.contains(id) else {
                    continue
                }
                group.addTask {
                    ProviderRuntimeFetch(
                        id: id,
                        providerName: provider.providerName,
                        runtimes: await provider.fetchRuntimes()
                    )
                }
            }

            for await fetch in group {
                runtimeFetches.append(fetch)
            }
        }

        let fetchedTasks = taskFetches.flatMap(\.tasks)
        let fetchedRuntimes = runtimeFetches.flatMap(\.runtimes)
        providerTasks = deduplicate(fetchedTasks)
        runtimes = deduplicate(fetchedRuntimes)
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind.title < rhs.kind.title
                }
                return lhs.name < rhs.name
            }
        diagnostics = makeDiagnostics(
            taskFetches: taskFetches,
            runtimeFetches: runtimeFetches,
            checkedAt: Date()
        )
        publishMergedTasks()
    }

    private func makeDiagnostics(
        taskFetches: [ProviderTaskFetch],
        runtimeFetches: [ProviderRuntimeFetch],
        checkedAt: Date
    ) -> [ProviderDiagnostic] {
        let taskCounts = Dictionary(uniqueKeysWithValues: taskFetches.map { ($0.id, $0.tasks.count) })
        let runtimeCounts = Dictionary(uniqueKeysWithValues: runtimeFetches.map { ($0.id, $0.runtimes.count) })
        let descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id.rawValue, $0) })

        return providerSettings.map { setting in
            let descriptor = descriptorByID[setting.id]
            let dataPaths = descriptor?.dataPaths ?? []
            guard setting.isEnabled else {
                return ProviderDiagnostic(
                    id: setting.id,
                    displayName: setting.displayName,
                    status: .disabled,
                    message: "Provider is turned off in Settings.",
                    dataPaths: dataPaths,
                    lastCheckedAt: checkedAt
                )
            }

            let foundPath = dataPaths.contains { pathExists($0) }
            let missingRequiredPath = !dataPaths.isEmpty && !foundPath
            let count = (taskCounts[setting.id] ?? 0) + (runtimeCounts[setting.id] ?? 0)

            if missingRequiredPath {
                return ProviderDiagnostic(
                    id: setting.id,
                    displayName: setting.displayName,
                    status: .missingPath,
                    message: "No configured local data path was found.",
                    dataPaths: dataPaths,
                    lastCheckedAt: checkedAt
                )
            }

            if count == 0 {
                return ProviderDiagnostic(
                    id: setting.id,
                    displayName: setting.displayName,
                    status: .noData,
                    message: "Provider is enabled, but no active or recent records were found.",
                    dataPaths: dataPaths,
                    lastCheckedAt: checkedAt
                )
            }

            return ProviderDiagnostic(
                id: setting.id,
                displayName: setting.displayName,
                status: .ok,
                message: "Found \(count) record\(count == 1 ? "" : "s").",
                dataPaths: dataPaths,
                lastCheckedAt: checkedAt
            )
        }
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
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: futureTasksStorageKey)
            ?? defaults.data(forKey: legacyFutureTasksStorageKey)
        else {
            return []
        }

        do {
            return try JSONDecoder().decode([FutureAgentTask].self, from: data)
        } catch {
            return []
        }
    }

    private static func loadProviderSettings(descriptors: [AgentProviderDescriptor]) -> [AgentProviderSetting] {
        let defaults = UserDefaults.standard
        let defaultSettings = defaultProviderSettings(descriptors: descriptors)
        let defaultsByID = Dictionary(uniqueKeysWithValues: defaultSettings.map { ($0.id, $0) })
        guard
            let data = defaults.data(forKey: providerSettingsStorageKey),
            let savedSettings = try? JSONDecoder().decode([AgentProviderSetting].self, from: data)
        else {
            return defaultSettings
        }

        var merged = defaultSettings
        for saved in savedSettings {
            let savedID = migratedProviderID(saved.id)
            guard let index = merged.firstIndex(where: { $0.id == savedID }) else {
                continue
            }
            let current = defaultsByID[savedID] ?? merged[index]
            merged[index] = AgentProviderSetting(
                id: current.id,
                displayName: current.displayName,
                detail: current.detail,
                isEnabled: saved.isEnabled
            )
        }
        return merged
    }

    private func persistProviderSettings() {
        do {
            let data = try JSONEncoder().encode(providerSettings)
            UserDefaults.standard.set(data, forKey: Self.providerSettingsStorageKey)
        } catch {
            assertionFailure("Failed to persist provider settings: \(error)")
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

private struct ProviderTaskFetch: Sendable {
    let id: String
    let providerName: String
    let tasks: [AgentTask]
}

private struct ProviderRuntimeFetch: Sendable {
    let id: String
    let providerName: String
    let runtimes: [AgentRuntime]
}

private func defaultProviderSettings(descriptors: [AgentProviderDescriptor]) -> [AgentProviderSetting] {
    descriptors.map { descriptor in
        AgentProviderSetting(
            id: descriptor.id.rawValue,
            displayName: descriptor.displayName,
            detail: descriptor.detail,
            isEnabled: descriptor.defaultEnabled
        )
    }
}

private func pathExists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

private func migratedProviderID(_ id: String) -> String {
    switch id {
    case "claude": AgentProviderID.claudeCLI.rawValue
    case "claudeDesktop": AgentProviderID.claudeDesktop.rawValue
    case "terminalAgents": AgentProviderID.terminalAgents.rawValue
    case "desktopApps": AgentProviderID.desktopApps.rawValue
    default: id
    }
}

private func initialDiagnostics(
    for settings: [AgentProviderSetting],
    descriptors: [AgentProviderDescriptor]
) -> [ProviderDiagnostic] {
    let descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id.rawValue, $0) })
    return settings.map { setting in
        ProviderDiagnostic(
            id: setting.id,
            displayName: setting.displayName,
            status: setting.isEnabled ? .noData : .disabled,
            message: setting.isEnabled ? "Not checked yet." : "Provider is turned off in Settings.",
            dataPaths: descriptorByID[setting.id]?.dataPaths ?? [],
            lastCheckedAt: nil
        )
    }
}
