import Foundation

struct CursorLocalProvider: AgentTaskProvider {
    let providerID = AgentProviderID.cursor
    let providerName = "Cursor"

    private static let runningActivityWindow: TimeInterval = 30 * 60
    private static let recentActivityWindow: TimeInterval = 24 * 60 * 60

    private let databaseURL: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        databaseURL = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Cursor", isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb")
    }

    func fetchTasks() async -> [AgentTask] {
        await Task.detached(priority: .utility) {
            readTasks()
        }.value
    }

    private func readTasks() -> [AgentTask] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return []
        }

        return queryComposerSessions(from: databaseURL)
            .compactMap(readTask(from:))
    }

    private func queryComposerSessions(from databaseURL: URL) -> [[String: Any]] {
        let sql = """
        select
            key,
            coalesce(json_extract(value, '$.composerId'), substr(key, 14)) as composer_id,
            json_extract(value, '$.name') as name,
            json_extract(value, '$.createdAt') as created_at,
            json_extract(value, '$.lastUpdatedAt') as last_updated_at,
            json_extract(value, '$.status') as status,
            json_extract(value, '$.isAgentic') as is_agentic,
            json_extract(value, '$.isDraft') as is_draft,
            json_array_length(value, '$.generatingBubbleIds') as generating_bubble_count,
            json_extract(value, '$.modelConfig.modelName') as model_name,
            json_extract(value, '$.modelConfig.selectedModel') as selected_model,
            json_extract(value, '$.modelConfig.selectedModels[0]') as selected_model0,
            json_extract(value, '$.usageData.totalTokens') as usage_total_tokens,
            json_extract(value, '$.tokenCount') as token_count
        from cursorDiskKV
        where key like 'composerData:%'
            and value is not null
            and json_valid(value)
        order by coalesce(json_extract(value, '$.lastUpdatedAt'), json_extract(value, '$.createdAt'), 0) desc
        limit 80;
        """

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", databaseURL.path, sql]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return rows
    }

    private func readTask(from row: [String: Any]) -> AgentTask? {
        guard
            let composerID = (row["composer_id"] as? String)?.nilIfEmpty,
            boolValue(row["is_agentic"]) == true
        else {
            return nil
        }

        let statusText = ((row["status"] as? String) ?? "").lowercased()
        let title = (row["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let isEmptyDraft = title == nil
            && (statusText.isEmpty || statusText == "none" || boolValue(row["is_draft"]))
        guard !isEmptyDraft else {
            return nil
        }

        let createdAt = dateFromMilliseconds(row["created_at"])
        let updatedAt = dateFromMilliseconds(row["last_updated_at"])
            ?? createdAt
            ?? Date.distantPast
        let status = taskStatus(
            statusText: statusText,
            updatedAt: updatedAt,
            hasTitle: title != nil,
            generatingBubbleCount: intValue(row["generating_bubble_count"])
        )

        return AgentTask(
            id: "cursor:\(composerID)",
            title: title ?? "Cursor 会话 \(composerID.prefix(8))",
            summary: summary(status: status, rawStatus: statusText),
            agent: "Cursor",
            providerID: providerID,
            model: modelName(from: row),
            tokenUsage: tokenUsage(from: row),
            status: status,
            updatedAt: updatedAt,
            openURL: databaseURL
        )
    }

    private func taskStatus(
        statusText: String,
        updatedAt: Date,
        hasTitle: Bool,
        generatingBubbleCount: Int
    ) -> AgentTaskStatus {
        if statusText.contains("abort")
            || statusText.contains("cancel")
            || statusText.contains("interrupt") {
            return .interrupted
        }

        let isRecent = Date().timeIntervalSince(updatedAt) < Self.runningActivityWindow
        if generatingBubbleCount > 0
            || statusText.contains("running")
            || statusText.contains("generating")
            || statusText.contains("streaming")
            || statusText.contains("applying")
            || (statusText == "none" && hasTitle && isRecent) {
            return isRecent ? .running : .completed
        }

        return Date().timeIntervalSince(updatedAt) < Self.recentActivityWindow ? .completed : .history
    }

    private func summary(status: AgentTaskStatus, rawStatus: String) -> String {
        switch status {
        case .running:
            return "Cursor Agent 正在处理"
        case .completed:
            return rawStatus == "completed" ? "Cursor Agent 最近完成" : "Cursor Agent 最近有本地 session 活动"
        case .interrupted:
            return "Cursor Agent 已中断"
        case .history:
            return "Cursor Agent 历史 session"
        }
    }

    private func modelName(from row: [String: Any]) -> String {
        let candidates = [
            row["model_name"] as? String,
            row["selected_model"] as? String,
            row["selected_model0"] as? String
        ]

        for candidate in candidates {
            if let value = candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
               !value.hasPrefix("{") {
                return value
            }
        }

        return "unknown"
    }

    private func tokenUsage(from row: [String: Any]) -> Int {
        max(
            intValue(row["usage_total_tokens"]),
            intValue(row["token_count"])
        )
    }

    private func dateFromMilliseconds(_ value: Any?) -> Date? {
        if let value = value as? Double {
            return Date(timeIntervalSince1970: value / 1000)
        }

        if let value = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
        }

        return nil
    }

    private func intValue(_ value: Any?) -> Int {
        if let value = value as? Int {
            return value
        }

        if let value = value as? Double {
            return Int(value)
        }

        return 0
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }

        if let value = value as? Int {
            return value != 0
        }

        if let value = value as? Double {
            return value != 0
        }

        return false
    }
}
