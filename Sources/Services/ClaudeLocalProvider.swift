import Foundation

struct ClaudeLocalProvider: AgentTaskProvider {
    let providerID = AgentProviderID.claudeCLI
    let providerName = "Claude"

    private let projectsDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        projectsDirectory = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    func fetchTasks() async -> [AgentTask] {
        await Task.detached(priority: .utility) {
            readTasks()
        }.value
    }

    func fetchUsageLimits() async -> ClaudeUsageLimitSummary? {
        await Task.detached(priority: .utility) {
            readUsageLimits()
        }.value
    }

    // MARK: - Usage Limits

    private func readUsageLimits() -> ClaudeUsageLimitSummary? {
        let files = findJSONLFiles(in: projectsDirectory)
        guard !files.isEmpty else { return nil }

        // Collect all (timestamp, usage, serviceTier) tuples
        var entries: [ClaudeUsageEntry] = []
        for file in files {
            entries.append(contentsOf: readUsageEntries(from: file))
        }
        guard !entries.isEmpty else { return nil }

        let now = Date()
        let sessionWindowDuration: TimeInterval = 5 * 60 * 60   // 5-hour rolling window
        let weekInterval: TimeInterval = 7 * 24 * 60 * 60

        let sessionCutoff = now.addingTimeInterval(-sessionWindowDuration)
        let weekCutoff = now.addingTimeInterval(-weekInterval)

        let sessionEntries = entries.filter { $0.timestamp >= sessionCutoff }
        let weekEntries = entries.filter { $0.timestamp >= weekCutoff }

        // Session window resets when the oldest entry in the window ages out
        let sessionResetsAt: Date
        if let oldest = sessionEntries.map(\.timestamp).min() {
            sessionResetsAt = oldest.addingTimeInterval(sessionWindowDuration)
        } else {
            sessionResetsAt = now.addingTimeInterval(sessionWindowDuration)
        }

        // Weekly window resets on next Thursday at 2:00 AM (matching Claude.ai convention)
        let weeklyResetsAt = nextThursday2AM(from: now)

        let latestServiceTier = entries
            .sorted { $0.timestamp > $1.timestamp }
            .first(where: { $0.serviceTier != nil })?
            .serviceTier

        return ClaudeUsageLimitSummary(
            sessionWindow: usageWindow(from: sessionEntries, resetsAt: sessionResetsAt),
            weeklyWindow: usageWindow(from: weekEntries, resetsAt: weeklyResetsAt),
            serviceTier: latestServiceTier,
            observedAt: entries.map(\.timestamp).max() ?? now
        )
    }

    private func readUsageEntries(from url: URL) -> [ClaudeUsageEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var entries: [ClaudeUsageEntry] = []

        for line in content.split(separator: "\n") {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = object["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any],
                let timestamp = parseDate(object["timestamp"] as? String)
            else {
                continue
            }

            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let outputTokens = usage["output_tokens"] as? Int ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let serviceTier = usage["service_tier"] as? String

            let total = inputTokens + outputTokens + cacheCreation + cacheRead
            guard total > 0 else { continue }

            entries.append(ClaudeUsageEntry(
                timestamp: timestamp,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheTokens: cacheCreation + cacheRead,
                serviceTier: serviceTier
            ))
        }

        return entries
    }

    private func usageWindow(from entries: [ClaudeUsageEntry], resetsAt: Date) -> ClaudeUsageWindow {
        ClaudeUsageWindow(
            tokens: entries.reduce(0) { $0 + $1.inputTokens + $1.outputTokens + $1.cacheTokens },
            turns: entries.count,
            resetsAt: resetsAt,
            inputTokens: entries.reduce(0) { $0 + $1.inputTokens },
            outputTokens: entries.reduce(0) { $0 + $1.outputTokens },
            cacheTokens: entries.reduce(0) { $0 + $1.cacheTokens }
        )
    }

    /// Returns the next Thursday at 02:00 local time (matching Claude.ai weekly reset)
    private func nextThursday2AM(from date: Date) -> Date {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "en_US")
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: date)
        components.weekday = 5  // Thursday
        components.hour = 2
        components.minute = 0
        components.second = 0
        guard let thursday = calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime
        ) else {
            return date.addingTimeInterval(7 * 24 * 60 * 60)
        }
        return thursday
    }

    // MARK: - Tasks

    private func readTasks() -> [AgentTask] {
        findJSONLFiles(in: projectsDirectory).compactMap(readClaudeTask(from:))
    }

    private func readClaudeTask(from url: URL) -> AgentTask? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        // Use filesystem modification time as a reliable "actively being written" signal
        let fileModDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date

        var sessionID = url.deletingPathExtension().lastPathComponent
        var title: String?
        var cwd: String?
        var model: String?
        var totalTokens = 0
        var lastTimestamp: Date?
        var lastSpeaker: String?
        // Track unresolved tool calls: Claude writes tool_use then waits for tool_result
        var pendingToolUseIDs = Set<String>()

        for line in content.split(separator: "\n") {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if let value = object["sessionId"] as? String {
                sessionID = value
            }

            if let customTitle = object["customTitle"] as? String, !customTitle.isEmpty {
                title = customTitle
            }

            if let value = object["cwd"] as? String {
                cwd = value
            }

            if let timestamp = parseDate(object["timestamp"] as? String) {
                lastTimestamp = max(lastTimestamp ?? timestamp, timestamp)
            }

            let type = object["type"] as? String
            if type == "user" {
                lastSpeaker = "user"
            } else if type == "assistant" {
                lastSpeaker = "assistant"
            }

            guard let message = object["message"] as? [String: Any] else {
                continue
            }

            if let value = message["model"] as? String {
                model = value
            }

            if let usage = message["usage"] as? [String: Any] {
                totalTokens = max(totalTokens, sumClaudeTokens(in: usage))
            }

            // Track tool_use blocks from assistant and tool_result blocks from user
            if let contentBlocks = message["content"] as? [[String: Any]] {
                for block in contentBlocks {
                    if let blockType = block["type"] as? String {
                        if blockType == "tool_use", let toolID = block["id"] as? String {
                            pendingToolUseIDs.insert(toolID)
                        } else if blockType == "tool_result", let toolID = block["tool_use_id"] as? String {
                            pendingToolUseIDs.remove(toolID)
                        }
                    }
                }
            }
        }

        let updatedAt = lastTimestamp ?? Date.distantPast
        let now = Date()
        // File actively being written to within last 90 seconds → running
        let fileBeingWritten = fileModDate.map { now.timeIntervalSince($0) < 90 } ?? false
        // Unresolved tool calls within a recent session → running
        let hasUnresolvedToolCalls = !pendingToolUseIDs.isEmpty && now.timeIntervalSince(updatedAt) < 15 * 60
        // Classic signal: last speaker is user (Claude hasn't responded yet) within 15 min
        let waitingForResponse = lastSpeaker == "user" && now.timeIntervalSince(updatedAt) < 15 * 60

        let isRunning = fileBeingWritten || hasUnresolvedToolCalls || waitingForResponse
        let status: AgentTaskStatus = isRunning ? .running : (now.timeIntervalSince(updatedAt) < 24 * 60 * 60 ? .completed : .history)
        let folderName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude 会话"

        return AgentTask(
            id: "claude:\(sessionID)",
            title: title ?? folderName,
            summary: status == .running ? "Claude 本机会话正在运行中" : "Claude 本机会话最近活动",
            agent: "Claude",
            providerID: providerID,
            model: model ?? "unknown",
            tokenUsage: totalTokens,
            status: status,
            updatedAt: updatedAt,
            openURL: url
        )
    }

    private func findJSONLFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else {
                return nil
            }
            return url
        }
    }

    private func sumClaudeTokens(in usage: [String: Any]) -> Int {
        let keys = [
            "input_tokens",
            "output_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens"
        ]

        return keys.reduce(0) { partialResult, key in
            partialResult + (usage[key] as? Int ?? 0)
        }
    }
}

private struct ClaudeUsageEntry {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheTokens: Int
    let serviceTier: String?
}
