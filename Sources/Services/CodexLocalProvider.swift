import Foundation

struct CodexLocalProvider: AgentTaskProvider {
    let providerID = AgentProviderID.codex
    let providerName = "Codex"

    private static let runningActivityWindow: TimeInterval = 30 * 60

    private let codexDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        codexDirectory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    func fetchTasks() async -> [AgentTask] {
        await Task.detached(priority: .utility) {
            readTasks()
        }.value
    }

    func fetchUsageLimits() async -> [CodexUsageLimitSummary] {
        await Task.detached(priority: .utility) {
            readUsageLimits()
        }.value
    }

    private func readTasks() -> [AgentTask] {
        let indexURL = codexDirectory.appendingPathComponent("session_index.jsonl")
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        let indexEntries = readSessionIndex(from: indexURL)
        let indexByID = Dictionary(uniqueKeysWithValues: indexEntries.map { ($0.id, $0) })

        let sessionFiles = findJSONLFiles(in: sessionsDirectory)
        var tasksByID: [String: AgentTask] = [:]

        for fileURL in sessionFiles {
            let metadata = readCodexSessionMetadata(from: fileURL)
            guard let sessionID = metadata.sessionID ?? extractCodexSessionID(from: fileURL.lastPathComponent) else {
                continue
            }

            let indexEntry = indexByID[sessionID]
            let updatedAt = metadata.lastTimestamp
                ?? indexEntry?.updatedAt
                ?? fileModifiedAt(fileURL)
                ?? Date.distantPast
            let status = status(for: metadata, updatedAt: updatedAt)

            let task = AgentTask(
                id: "codex:\(sessionID)",
                title: indexEntry?.threadName
                    ?? metadata.title
                    ?? "Codex 会话 \(sessionID.prefix(8))",
                summary: codexSummary(
                    statusEvent: metadata.lastTaskEvent,
                    cwd: metadata.cwd,
                    status: status
                ),
                agent: "Codex",
                providerID: providerID,
                model: metadata.model ?? "unknown",
                tokenUsage: metadata.totalTokens,
                status: status,
                updatedAt: updatedAt,
                openURL: fileURL
            )

            if let existing = tasksByID[task.id], existing.updatedAt > task.updatedAt {
                continue
            }
            tasksByID[task.id] = task
        }

        for entry in indexEntries where tasksByID["codex:\(entry.id)"] == nil {
            tasksByID["codex:\(entry.id)"] = AgentTask(
                id: "codex:\(entry.id)",
                title: entry.threadName,
                summary: "Codex 会话已记录，未找到本地事件流",
                agent: "Codex",
                providerID: providerID,
                model: "unknown",
                tokenUsage: 0,
                status: status(for: entry.updatedAt),
                updatedAt: entry.updatedAt
            )
        }

        return Array(tasksByID.values)
    }

    private func readSessionIndex(from url: URL) -> [CodexIndexEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { line -> CodexIndexEntry? in
                guard
                    let data = String(line).data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let id = object["id"] as? String
                else {
                    return nil
                }

                let threadName = object["thread_name"] as? String ?? "Codex 会话 \(id.prefix(8))"
                let updatedAt = parseDate(object["updated_at"] as? String) ?? Date.distantPast
                return CodexIndexEntry(id: id, threadName: threadName, updatedAt: updatedAt)
            }
    }

    private func readCodexSessionMetadata(from url: URL) -> CodexSessionMetadata {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return CodexSessionMetadata()
        }

        var metadata = CodexSessionMetadata()

        for line in content.split(separator: "\n") {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if let timestamp = parseDate(object["timestamp"] as? String) {
                metadata.lastTimestamp = max(metadata.lastTimestamp ?? timestamp, timestamp)
            }

            guard let payload = object["payload"] as? [String: Any] else {
                continue
            }

            if object["type"] as? String == "session_meta" {
                if let id = payload["id"] as? String {
                    metadata.sessionID = id
                }

                if let cwd = payload["cwd"] as? String {
                    metadata.cwd = cwd
                }
            }

            if let cwd = payload["cwd"] as? String {
                metadata.cwd = cwd
            }

            if let model = payload["model"] as? String {
                metadata.model = model
            } else if
                let collaborationMode = payload["collaboration_mode"] as? [String: Any],
                let settings = collaborationMode["settings"] as? [String: Any],
                let model = settings["model"] as? String {
                metadata.model = model
            }

            if object["type"] as? String == "event_msg",
               let eventType = payload["type"] as? String,
               eventType == "task_started" || eventType == "task_complete" || eventType == "turn_aborted" {
                metadata.lastTaskEvent = eventType
            }

            if
                let info = payload["info"] as? [String: Any],
                let usage = info["total_token_usage"] as? [String: Any],
                let tokens = usage["total_tokens"] as? Int {
                metadata.totalTokens = max(metadata.totalTokens, tokens)
            } else if
                let usage = payload["total_token_usage"] as? [String: Any],
                let tokens = usage["total_tokens"] as? Int {
                metadata.totalTokens = max(metadata.totalTokens, tokens)
            }

            if metadata.title == nil {
                metadata.title = titleCandidate(from: object, payload: payload)
            }
        }

        return metadata
    }

    private func readUsageLimits() -> [CodexUsageLimitSummary] {
        // Only scan active sessions — archived sessions contain stale historical data
        // that creates misleading duplicate limit groups in the UI.
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        let sessionFiles = findJSONLFiles(in: sessionsDirectory).sorted { lhs, rhs in
            (fileModifiedAt(lhs) ?? .distantPast) > (fileModifiedAt(rhs) ?? .distantPast)
        }

        // Try recent files first (covers most cases quickly)
        let groups = readUsageLimitGroups(from: Array(sessionFiles.prefix(48)), maxAgeDays: 7)
        if !groups.isEmpty { return groups }

        // Fall back to all session files with the same recency filter
        return readUsageLimitGroups(from: sessionFiles, maxAgeDays: 7)
    }

    /// Returns one summary per distinct `limit_id`, using only the latest snapshot.
    /// Entries whose most-recent data is older than `maxAgeDays` are excluded.
    private func readUsageLimitGroups(from sessionFiles: [URL], maxAgeDays: Double) -> [CodexUsageLimitSummary] {
        let cutoff = Date().addingTimeInterval(-maxAgeDays * 86400)
        var latestByID: [String: CodexUsageLimitSummary] = [:]

        for fileURL in sessionFiles {
            // Skip files older than the cutoff — no useful data inside
            guard let modDate = fileModifiedAt(fileURL), modDate >= cutoff else { continue }

            let snapshots = readUsageLimitSnapshots(from: fileURL)
            for (limitID, snapshot) in snapshots {
                guard let s = snapshot.latest else { continue }
                if latestByID[limitID] == nil || s.observedAt > latestByID[limitID]!.observedAt {
                    latestByID[limitID] = s
                }
            }
        }

        // Drop any entry whose most-recent snapshot is too old
        let fresh = latestByID.values.filter { $0.observedAt >= cutoff }

        // Sort: named limits first (by name), unnamed last
        return fresh.sorted { lhs, rhs in
            switch (lhs.limitName, rhs.limitName) {
            case (let a?, let b?): return a < b
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    /// Returns a dict of limitID → snapshot for all distinct limit_ids in the file.
    private func readUsageLimitSnapshots(from fileURL: URL) -> [String: CodexUsageLimitSnapshot] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return [:]
        }

        var latestByID: [String: CodexUsageLimitSummary] = [:]
        var latestNonZeroByID: [String: CodexUsageLimitSummary] = [:]

        for line in content.split(separator: "\n").reversed() {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = object["payload"] as? [String: Any],
                let rateLimits = payload["rate_limits"] as? [String: Any],
                let summary = codexUsageLimitSummary(from: rateLimits, timestamp: parseDate(object["timestamp"] as? String))
            else {
                continue
            }

            let id = summary.limitID ?? "unknown"

            if latestByID[id] == nil {
                latestByID[id] = summary
            }
            if latestNonZeroByID[id] == nil, isNonZeroUsageLimit(summary) {
                latestNonZeroByID[id] = summary
            }
        }

        var result: [String: CodexUsageLimitSnapshot] = [:]
        let allIDs = Set(latestByID.keys).union(latestNonZeroByID.keys)
        for id in allIDs {
            result[id] = CodexUsageLimitSnapshot(latest: latestByID[id], latestNonZero: latestNonZeroByID[id])
        }
        return result
    }

    private func codexUsageLimitSummary(
        from rateLimits: [String: Any],
        timestamp: Date?
    ) -> CodexUsageLimitSummary? {
        guard
            let primaryObject = rateLimits["primary"] as? [String: Any],
            let primary = codexUsageLimit(from: primaryObject)
        else {
            return nil
        }

        let secondary = (rateLimits["secondary"] as? [String: Any]).flatMap(codexUsageLimit)

        return CodexUsageLimitSummary(
            limitID: rateLimits["limit_id"] as? String,
            limitName: rateLimits["limit_name"] as? String,
            primary: primary,
            secondary: secondary,
            observedAt: timestamp ?? Date.distantPast
        )
    }

    private func codexUsageLimit(from object: [String: Any]) -> CodexUsageLimit? {
        guard
            let usedPercent = doubleValue(object["used_percent"]),
            let windowMinutes = intValue(object["window_minutes"]),
            let resetSeconds = doubleValue(object["resets_at"])
        else {
            return nil
        }

        return CodexUsageLimit(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: Date(timeIntervalSince1970: resetSeconds)
        )
    }

    private func isNonZeroUsageLimit(_ summary: CodexUsageLimitSummary) -> Bool {
        summary.primary.usedPercent > 0 || (summary.secondary?.usedPercent ?? 0) > 0
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

    private func extractCodexSessionID(from fileName: String) -> String? {
        let trimmed = fileName.replacingOccurrences(of: ".jsonl", with: "")
        return trimmed.split(separator: "-").suffix(5).joined(separator: "-").nilIfEmpty
    }

    private func codexSummary(statusEvent: String?, cwd: String?, status: AgentTaskStatus) -> String {
        let location = cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nilIfEmpty }

        switch statusEvent {
        case "task_started" where status == .running:
            return location.map { "正在处理本地任务：\($0)" } ?? "正在处理本地 Codex 任务"
        case "task_started":
            return location.map { "任务已停止更新：\($0)" } ?? "Codex 任务已停止更新"
        case "task_complete":
            return location.map { "最近完成于：\($0)" } ?? "最近完成一个 Codex 任务"
        case "turn_aborted":
            return location.map { "任务已中断于：\($0)" } ?? "Codex 任务已中断"
        default:
            return location.map { "最近活动目录：\($0)" } ?? "Codex 本机会话"
        }
    }

    private func status(for updatedAt: Date) -> AgentTaskStatus {
        return Date().timeIntervalSince(updatedAt) < 24 * 60 * 60 ? .completed : .history
    }

    private func status(for metadata: CodexSessionMetadata, updatedAt: Date) -> AgentTaskStatus {
        switch metadata.lastTaskEvent {
        case "task_started":
            return isActivelyRunning(metadata: metadata, updatedAt: updatedAt) ? .running : status(for: updatedAt)
        case "turn_aborted":
            return Date().timeIntervalSince(updatedAt) < 24 * 60 * 60 ? .interrupted : .history
        default:
            return status(for: updatedAt)
        }
    }

    private func isActivelyRunning(metadata: CodexSessionMetadata, updatedAt: Date) -> Bool {
        guard metadata.lastTaskEvent == "task_started" else {
            return false
        }

        return Date().timeIntervalSince(updatedAt) < Self.runningActivityWindow
    }

    private func fileModifiedAt(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func titleCandidate(from object: [String: Any], payload: [String: Any]) -> String? {
        if object["type"] as? String == "event_msg",
           let eventType = payload["type"] as? String,
           eventType == "user_message",
           let message = payload["message"] as? String {
            return trimmedTitle(message)
        }

        guard
            object["type"] as? String == "response_item",
            payload["type"] as? String == "message",
            payload["role"] as? String == "user",
            let content = payload["content"] as? [[String: Any]]
        else {
            return nil
        }

        for item in content {
            if let text = item["text"] as? String {
                return trimmedTitle(text)
            }
        }

        return nil
    }

    private func trimmedTitle(_ value: String) -> String? {
        let title = value
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let title, !title.isEmpty else {
            return nil
        }

        guard !title.hasPrefix("<environment_context>"),
              !title.hasPrefix("<turn_aborted>") else {
            return nil
        }

        if title.count <= 80 {
            return title
        }

        return "\(title.prefix(80))..."
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }

        if let double = value as? Double {
            return Int(double)
        }

        if let string = value as? String {
            return Int(string)
        }

        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }

        if let int = value as? Int {
            return Double(int)
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
    }
}

private struct CodexIndexEntry {
    let id: String
    let threadName: String
    let updatedAt: Date
}

private struct CodexSessionMetadata {
    var sessionID: String?
    var lastTimestamp: Date?
    var lastTaskEvent: String?
    var title: String?
    var model: String?
    var cwd: String?
    var totalTokens = 0
}

private struct CodexUsageLimitSnapshot {
    let latest: CodexUsageLimitSummary?
    let latestNonZero: CodexUsageLimitSummary?
}
