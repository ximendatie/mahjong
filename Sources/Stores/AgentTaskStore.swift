import Foundation

@MainActor
final class AgentTaskStore: ObservableObject {
    @Published private(set) var tasks: [AgentTask]
    @Published private(set) var runtimes: [AgentRuntime]
    @Published private(set) var futureTasks: [FutureTaskItem]
    @Published private(set) var completionPulseID: UUID?
    @Published private(set) var providerSettings: [AgentProviderSetting]
    @Published private(set) var diagnostics: [ProviderDiagnostic]
    @Published private(set) var isPrivacyModeEnabled: Bool
    @Published private(set) var isMenuBarEnabled: Bool
    @Published private(set) var isDockIconEnabled: Bool
    @Published private(set) var unreadCompletedCount: Int

    private static let futureTasksStorageKey = "local.mahjong.futureTasks"
    private static let legacyFutureTasksStorageKey = "local.agentspet.futureTasks"
    private static let providerSettingsStorageKey = "local.mahjong.providerSettings"
    private static let privacyModeStorageKey = "local.mahjong.privacyMode"
    private static let menuBarModeStorageKey = "local.mahjong.menuBarMode"
    private static let dockIconModeStorageKey = "local.mahjong.dockIconMode"
    private static let readCompletedTaskIDsStorageKey = "local.mahjong.readCompletedTaskIDs"

    private let descriptors: [AgentProviderDescriptor]
    private let providers: [AgentTaskProvider]
    private let runtimeProviders: [AgentRuntimeProvider]
    private let isChatGPTAccessibilityTrusted: () -> Bool
    private var providerTasks: [AgentTask] = []
    private var localStatusOverrides: [String: AgentTaskStatus] = [:]
    private var localUpdatedAtOverrides: [String: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var knownCompletedTaskIDs: Set<String> = []
    private var readCompletedTaskIDs: Set<String>
    private var hasInitializedCompletedReadState: Bool

    init(
        descriptors: [AgentProviderDescriptor]? = nil,
        providers: [AgentTaskProvider]? = nil,
        runtimeProviders: [AgentRuntimeProvider]? = nil,
        isChatGPTAccessibilityTrusted: @escaping () -> Bool = { ChatGPTAccessibilityDetector.isTrusted }
    ) {
        self.descriptors = descriptors ?? AgentProviderDescriptor.defaults()
        self.providers = providers ?? [
            CodexLocalProvider(),
            CursorLocalProvider(),
            ChatGPTLocalProvider(),
            ClaudeLocalProvider(),
            ClaudeDesktopLocalProvider(),
            HermesLocalProvider(),
            OpenClawLocalProvider(),
            TraeCNLocalProvider()
        ]
        self.runtimeProviders = runtimeProviders ?? [
            TerminalAgentRuntimeProvider(),
            DesktopAppRuntimeProvider()
        ]
        self.isChatGPTAccessibilityTrusted = isChatGPTAccessibilityTrusted

        tasks = []
        runtimes = []
        let loadedFutureTasks = Self.normalizedFutureTasks(Self.loadFutureTasks())
        futureTasks = loadedFutureTasks
        let loadedProviderSettings = Self.loadProviderSettings(descriptors: self.descriptors)
        providerSettings = loadedProviderSettings
        diagnostics = initialDiagnostics(for: loadedProviderSettings, descriptors: self.descriptors)
        isPrivacyModeEnabled = UserDefaults.standard.bool(forKey: Self.privacyModeStorageKey)
        isMenuBarEnabled = UserDefaults.standard.object(forKey: Self.menuBarModeStorageKey) as? Bool ?? true
        isDockIconEnabled = UserDefaults.standard.object(forKey: Self.dockIconModeStorageKey) as? Bool ?? true
        let loadedReadCompletedTaskIDs = Self.loadReadCompletedTaskIDs()
        readCompletedTaskIDs = loadedReadCompletedTaskIDs ?? []
        hasInitializedCompletedReadState = loadedReadCompletedTaskIDs != nil
        unreadCompletedCount = 0
        knownCompletedTaskIDs = Set(tasks.filter { $0.status == .completed }.map(\.id))

        if loadedFutureTasks != Self.loadFutureTasks() {
            persistFutureTasks()
        }
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

    var hasUnreadCompletedTasks: Bool {
        unreadCompletedCount > 0
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

    func setMenuBarEnabled(_ isEnabled: Bool) {
        isMenuBarEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.menuBarModeStorageKey)
    }

    func setDockIconEnabled(_ isEnabled: Bool) {
        isDockIconEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.dockIconModeStorageKey)
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

    func tokenUsageSummaries(
        for range: TokenUsageTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TokenUsageSummary] {
        let filteredTasks = tasks.filter { task in
            task.tokenUsage > 0 && range.contains(task.updatedAt, now: now, calendar: calendar)
        }
        var summariesByID: [String: TokenUsageSummary] = [:]

        for task in filteredTasks {
            let agentName = task.agent.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = agentName.isEmpty ? (task.providerID?.rawValue ?? "Unknown") : agentName
            let id = task.providerID?.rawValue ?? displayName

            if var summary = summariesByID[id] {
                summary.taskCount += 1
                summary.totalTokens += task.tokenUsage
                summary.latestActivityAt = max(summary.latestActivityAt, task.updatedAt)
                summariesByID[id] = summary
            } else {
                summariesByID[id] = TokenUsageSummary(
                    agent: displayName,
                    providerID: task.providerID,
                    taskCount: 1,
                    totalTokens: task.tokenUsage,
                    latestActivityAt: task.updatedAt
                )
            }
        }

        return summariesByID.values.sorted { lhs, rhs in
            if lhs.totalTokens != rhs.totalTokens {
                return lhs.totalTokens > rhs.totalTokens
            }
            return lhs.agent.localizedStandardCompare(rhs.agent) == .orderedAscending
        }
    }

    /// Cumulative tokens per agent display-name (lowercased), used to annotate
    /// running runtimes in the "运行 Agent" view. Empty in privacy mode.
    func runtimeTokenTotals() -> [String: Int] {
        guard !isPrivacyModeEnabled else { return [:] }
        var totals: [String: Int] = [:]
        for summary in tokenUsageSummaries(for: .all) {
            totals[summary.agent.lowercased()] = summary.totalTokens
        }
        return totals
    }

    func sortedFutureTasks() -> [FutureTaskItem] {
        futureTasks
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted && rhs.isCompleted
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func createFutureTask(
        title: String,
        note: String
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedNote.isEmpty else {
            return
        }

        let task = FutureTaskItem(
            title: trimmedTitle.isEmpty ? trimmedNote.firstLineTitle : trimmedTitle,
            note: trimmedNote,
            sortOrder: nextFutureTaskSortOrder(isCompleted: false)
        )

        futureTasks.append(task)
        persistFutureTasks()
    }

    func updateFutureTask(
        id: FutureTaskItem.ID,
        title: String,
        note: String
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedNote.isEmpty,
              let index = futureTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        futureTasks[index].title = trimmedTitle.isEmpty ? trimmedNote.firstLineTitle : trimmedTitle
        futureTasks[index].note = trimmedNote
        futureTasks[index].updatedAt = Date()
        persistFutureTasks()
    }

    func setFutureTaskCompleted(id: FutureTaskItem.ID, isCompleted: Bool) {
        guard let index = futureTasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        futureTasks[index].isCompleted = isCompleted
        futureTasks[index].sortOrder = nextFutureTaskSortOrder(isCompleted: isCompleted)
        futureTasks[index].updatedAt = Date()
        persistFutureTasks()
    }

    func moveFutureTask(id: FutureTaskItem.ID, before targetID: FutureTaskItem.ID) {
        guard id != targetID,
              let sourceTask = futureTasks.first(where: { $0.id == id }),
              let targetTask = futureTasks.first(where: { $0.id == targetID }),
              sourceTask.isCompleted == targetTask.isCompleted else {
            return
        }

        var group = futureTasks
            .filter { $0.isCompleted == sourceTask.isCompleted }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.updatedAt > rhs.updatedAt
            }

        guard let fromIndex = group.firstIndex(where: { $0.id == id }),
              let toIndex = group.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let movingTask = group.remove(at: fromIndex)
        let destinationIndex = fromIndex < toIndex ? max(0, toIndex - 1) : toIndex
        group.insert(movingTask, at: destinationIndex)

        reassignFutureTaskSortOrders(for: sourceTask.isCompleted, using: group)
        persistFutureTasks()
    }

    func deleteFutureTask(id: FutureTaskItem.ID) {
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
    }

    func markCompletedTasksRead() {
        let completedTaskIDs = Set(tasks.filter { $0.status == .completed }.map(\.id))
        guard !completedTaskIDs.isEmpty else {
            unreadCompletedCount = 0
            return
        }

        readCompletedTaskIDs.formUnion(completedTaskIDs)
        persistReadCompletedTaskIDs()
        unreadCompletedCount = 0
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

            if setting.id == AgentProviderID.chatGPT.rawValue,
               isChatGPTDesktopRunning(in: runtimeFetches),
               !isChatGPTAccessibilityTrusted() {
                return ProviderDiagnostic(
                    id: setting.id,
                    displayName: setting.displayName,
                    status: .failed,
                    message: "ChatGPT Desktop is running, but Accessibility is not allowed. Grant mahjong access in System Settings > Privacy & Security > Accessibility so it can detect when ChatGPT is generating. Conversation text is still not read.",
                    dataPaths: dataPaths,
                    lastCheckedAt: checkedAt
                )
            }

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

    private func isChatGPTDesktopRunning(in runtimeFetches: [ProviderRuntimeFetch]) -> Bool {
        runtimeFetches
            .flatMap(\.runtimes)
            .contains { runtime in
                runtime.bundleIdentifier == "com.openai.chat" || runtime.id == "desktop:chatgpt"
            }
    }

    private func publishMergedTasks() {
        tasks = deduplicate(archiveResolvedBeforeToday(applyLocalOverrides(to: providerTasks)))
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return statusSortIndex(lhs.status) < statusSortIndex(rhs.status)
                }
                return lhs.updatedAt > rhs.updatedAt
        }

        let completedTaskIDs = Set(tasks.filter { $0.status == .completed }.map(\.id))
        if !hasInitializedCompletedReadState {
            readCompletedTaskIDs.formUnion(completedTaskIDs)
            hasInitializedCompletedReadState = true
            persistReadCompletedTaskIDs()
        } else {
            let newlyCompletedTaskIDs = completedTaskIDs.subtracting(knownCompletedTaskIDs)
            let unreadNewlyCompletedTaskIDs = newlyCompletedTaskIDs.subtracting(readCompletedTaskIDs)
            if !unreadNewlyCompletedTaskIDs.isEmpty {
                readCompletedTaskIDs.subtract(unreadNewlyCompletedTaskIDs)
                persistReadCompletedTaskIDs()
                completionPulseID = UUID()
            }
        }

        readCompletedTaskIDs.formIntersection(completedTaskIDs)
        persistReadCompletedTaskIDs()
        unreadCompletedCount = completedTaskIDs.subtracting(readCompletedTaskIDs).count
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

    private func archiveResolvedBeforeToday(_ tasks: [AgentTask]) -> [AgentTask] {
        let calendar = Calendar.current
        return tasks.map { task in
            guard (task.status == .completed || task.status == .interrupted),
                  !calendar.isDateInToday(task.updatedAt) else {
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
        case .interrupted: 2
        case .history: 3
        }
    }

    private static func loadFutureTasks() -> [FutureTaskItem] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: futureTasksStorageKey)
            ?? defaults.data(forKey: legacyFutureTasksStorageKey)
        else {
            return []
        }

        do {
            return try JSONDecoder().decode([FutureTaskItem].self, from: data)
        } catch {
            return []
        }
    }

    private static func normalizedFutureTasks(_ tasks: [FutureTaskItem]) -> [FutureTaskItem] {
        var normalized = tasks
        var nextOrder = 0

        for isCompleted in [false, true] {
            let orderedIDs = normalized
                .enumerated()
                .filter { $0.element.isCompleted == isCompleted }
                .sorted { lhs, rhs in
                    if lhs.element.sortOrder != rhs.element.sortOrder {
                        return lhs.element.sortOrder < rhs.element.sortOrder
                    }
                    return lhs.element.updatedAt > rhs.element.updatedAt
                }
                .map(\.offset)

            for index in orderedIDs {
                normalized[index].sortOrder = nextOrder
                nextOrder += 1
            }
        }

        return normalized
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
            assertionFailure("Failed to persist future plans: \(error)")
        }
    }

    private func nextFutureTaskSortOrder(isCompleted: Bool) -> Int {
        let currentMinimum = futureTasks
            .filter { $0.isCompleted == isCompleted }
            .map(\.sortOrder)
            .min()

        return (currentMinimum ?? 0) - 1
    }

    private func reassignFutureTaskSortOrders(for isCompleted: Bool, using orderedTasks: [FutureTaskItem]) {
        let otherTasks = futureTasks.filter { $0.isCompleted != isCompleted }
        var reorderedByID = Dictionary(uniqueKeysWithValues: orderedTasks.enumerated().map { offset, task in
            var updatedTask = task
            updatedTask.sortOrder = offset
            return (updatedTask.id, updatedTask)
        })

        futureTasks = otherTasks + futureTasks.compactMap { task in
            guard task.isCompleted == isCompleted else {
                return nil
            }
            return reorderedByID.removeValue(forKey: task.id)
        }
    }

    private static func loadReadCompletedTaskIDs() -> Set<String>? {
        guard let data = UserDefaults.standard.data(forKey: readCompletedTaskIDsStorageKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(Set<String>.self, from: data)
        } catch {
            return []
        }
    }

    private func persistReadCompletedTaskIDs() {
        do {
            let data = try JSONEncoder().encode(readCompletedTaskIDs)
            UserDefaults.standard.set(data, forKey: Self.readCompletedTaskIDsStorageKey)
        } catch {
            assertionFailure("Failed to persist read completed task IDs: \(error)")
        }
    }
}

private extension String {
    var firstLineTitle: String {
        let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? self
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 28 else {
            return trimmed.isEmpty ? "未命名事项" : trimmed
        }
        return "\(trimmed.prefix(28))..."
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
