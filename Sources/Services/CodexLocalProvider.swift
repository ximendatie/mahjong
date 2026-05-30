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
