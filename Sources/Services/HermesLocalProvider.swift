import Foundation

struct HermesLocalProvider: AgentTaskProvider {
    let providerName = "Hermes"

    private let hermesDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        hermesDirectory = homeDirectory.appendingPathComponent(".hermes", isDirectory: true)
    }

    func fetchTasks() async -> [AgentTask] {
        await Task.detached(priority: .utility) {
            readTasks()
        }.value
    }

    private func readTasks() -> [AgentTask] {
        let databaseURL = hermesDirectory.appendingPathComponent("state.db")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return []
        }

        let rows = querySessions(from: databaseURL)
        return rows.compactMap(readTask(from:))
    }

    private func querySessions(from databaseURL: URL) -> [[String: Any]] {
        let sql = """
        select
            s.id,
            s.source,
            s.model,
            s.started_at,
            s.ended_at,
            s.end_reason,
            s.message_count,
            s.tool_call_count,
            s.input_tokens,
            s.output_tokens,
            s.cache_read_tokens,
            s.cache_write_tokens,
            s.title,
            max(m.timestamp) as last_message_at,
            (
                select content
                from messages
                where session_id = s.id and role = 'user'
                order by timestamp asc
                limit 1
            ) as first_user_message,
            (
                select finish_reason
                from messages
                where session_id = s.id and role = 'assistant' and finish_reason is not null
                order by timestamp desc
                limit 1
            ) as last_assistant_finish_reason
        from sessions s
        left join messages m on m.session_id = s.id
        group by s.id
        order by coalesce(max(m.timestamp), s.ended_at, s.started_at) desc
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
        guard let id = row["id"] as? String else {
            return nil
        }

        let title = (row["title"] as? String)?.nilIfEmpty
            ?? (row["first_user_message"] as? String)?.nilIfEmpty
            ?? "Hermes 会话 \(id.prefix(8))"
        let source = (row["source"] as? String)?.nilIfEmpty ?? "cli"
        let model = (row["model"] as? String)?.nilIfEmpty ?? "unknown"
        let startedAt = dateFromSeconds(row["started_at"]) ?? Date.distantPast
        let lastMessageAt = dateFromSeconds(row["last_message_at"])
        let endedAt = dateFromSeconds(row["ended_at"])
        let updatedAt = lastMessageAt ?? endedAt ?? startedAt
        let hasAssistantCompletion = (row["last_assistant_finish_reason"] as? String)?.nilIfEmpty != nil
        let isStaleOpenSession = endedAt == nil
            && !hasAssistantCompletion
            && Date().timeIntervalSince(updatedAt) > 2 * 60
        let tokenUsage = intValue(row["input_tokens"])
            + intValue(row["output_tokens"])
            + intValue(row["cache_read_tokens"])
            + intValue(row["cache_write_tokens"])
        let status: AgentTaskStatus
        if endedAt == nil && !hasAssistantCompletion && !isStaleOpenSession {
            status = .running
        } else if Date().timeIntervalSince(updatedAt) < 24 * 60 * 60 {
            status = .completed
        } else {
            status = .history
        }

        return AgentTask(
            id: "hermes:\(id)",
            title: title,
            summary: summary(source: source, status: status, endReason: row["end_reason"] as? String),
            agent: "Hermes",
            model: model,
            tokenUsage: tokenUsage,
            status: status,
            updatedAt: updatedAt,
            openURL: hermesDirectory.appendingPathComponent("state.db")
        )
    }

    private func summary(source: String, status: AgentTaskStatus, endReason: String?) -> String {
        let sourceTitle = source == "cli" ? "CLI" : source
        switch status {
        case .running:
            return "Hermes \(sourceTitle) 正在处理"
        case .completed:
            return endReason.map { "Hermes \(sourceTitle) 最近完成：\($0)" } ?? "Hermes \(sourceTitle) 最近完成"
        case .history:
            return endReason.map { "Hermes \(sourceTitle) 历史会话：\($0)" } ?? "Hermes \(sourceTitle) 历史会话"
        }
    }

    private func dateFromSeconds(_ value: Any?) -> Date? {
        if let value = value as? Double {
            return Date(timeIntervalSince1970: value)
        }

        if let value = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(value))
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
}
