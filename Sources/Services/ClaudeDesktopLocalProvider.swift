import Foundation

struct ClaudeDesktopLocalProvider: AgentTaskProvider {
    let providerID = AgentProviderID.claudeDesktop
    let providerName = "Claude Desktop"

    private let applicationSupportDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        applicationSupportDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude-3p", isDirectory: true)
    }

    func fetchTasks() async -> [AgentTask] {
        await Task.detached(priority: .utility) {
            readTasks()
        }.value
    }

    private func readTasks() -> [AgentTask] {
        let runningCLISessionIDs = readRunningCLISessionIDs()
        let sessionRoots: [(URL, ClaudeDesktopSessionKind)] = [
            (
                applicationSupportDirectory.appendingPathComponent("local-agent-mode-sessions", isDirectory: true),
                .cowork
            ),
            (
                applicationSupportDirectory.appendingPathComponent("claude-code-sessions", isDirectory: true),
                .code
            )
        ]

        return sessionRoots.flatMap { root, kind in
            findSessionMetadataFiles(in: root).compactMap { url in
                readTask(from: url, kind: kind, runningCLISessionIDs: runningCLISessionIDs)
            }
        }
    }

    private func readTask(
        from url: URL,
        kind: ClaudeDesktopSessionKind,
        runningCLISessionIDs: Set<String>
    ) -> AgentTask? {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let sessionID = object["sessionId"] as? String ?? url.deletingPathExtension().lastPathComponent
        let cliSessionID = object["cliSessionId"] as? String
        let title = (object["title"] as? String)?.nilIfEmpty
            ?? (object["initialMessage"] as? String)?.nilIfEmpty
            ?? kind.defaultTitle
        let cwd = (object["originCwd"] as? String)?.nilIfEmpty
            ?? (object["cwd"] as? String)?.nilIfEmpty
        let model = (object["model"] as? String)?.nilIfEmpty ?? "unknown"
        let updatedAt = dateFromMilliseconds(object["lastActivityAt"])
            ?? dateFromMilliseconds(object["lastFocusedAt"])
            ?? dateFromMilliseconds(object["createdAt"])
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date.distantPast
        let isArchived = object["isArchived"] as? Bool ?? false
        let isAgentCompleted = object["isAgentCompleted"] as? Bool
        let hasRunningCLIProcess = cliSessionID.map { runningCLISessionIDs.contains($0) } ?? false
        let auditState = readAuditState(metadataURL: url)

        let status: AgentTaskStatus
        if isArchived || Date().timeIntervalSince(updatedAt) >= 24 * 60 * 60 {
            status = .history
        } else if isAgentCompleted == true || auditState == .completed {
            status = .completed
        } else if auditState == .running || hasRunningCLIProcess {
            status = .running
        } else {
            status = .completed
        }

        return AgentTask(
            id: "claude-desktop:\(kind.rawValue):\(sessionID)",
            title: title,
            summary: summary(kind: kind, status: status, cwd: cwd),
            agent: "Claude Desktop",
            providerID: providerID,
            model: model,
            tokenUsage: readTokenUsage(metadataURL: url),
            status: status,
            updatedAt: updatedAt,
            openURL: url
        )
    }

    private func findSessionMetadataFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard
                let url = item as? URL,
                url.pathExtension == "json",
                url.deletingPathExtension().lastPathComponent.hasPrefix("local_")
            else {
                return nil
            }
            return url
        }
    }

    private func readRunningCLISessionIDs() -> Set<String> {
        let output = ProcessListReader.readProcessList()
        var sessionIDs: Set<String> = []

        for line in output.split(separator: "\n") {
            guard let args = ProcessListReader.arguments(from: line) else {
                continue
            }

            let lowercased = args.lowercased()
            guard lowercased.contains("claude-3p") && lowercased.contains("/claude") else {
                continue
            }

            if let sessionID = value(after: "--resume", in: args) {
                sessionIDs.insert(sessionID)
            }
        }

        return sessionIDs
    }

    private func value(after flag: String, in arguments: String) -> String? {
        let parts = arguments.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let flagIndex = parts.firstIndex(of: Substring(flag)) else {
            return nil
        }

        let valueIndex = parts.index(after: flagIndex)
        guard valueIndex < parts.endIndex else {
            return nil
        }

        return String(parts[valueIndex])
    }

    private func readTokenUsage(metadataURL: URL) -> Int {
        let auditURL = auditURL(for: metadataURL)
        guard let content = try? String(contentsOf: auditURL, encoding: .utf8) else {
            return 0
        }

        var maxTokens = 0
        for line in content.split(separator: "\n") {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = object["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            else {
                continue
            }

            maxTokens = max(maxTokens, sumClaudeTokens(in: usage))
        }

        return maxTokens
    }

    private func readAuditState(metadataURL: URL) -> ClaudeDesktopAuditState {
        let auditURL = auditURL(for: metadataURL)
        guard let content = try? String(contentsOf: auditURL, encoding: .utf8) else {
            return .unknown
        }

        var state = ClaudeDesktopAuditState.unknown
        for line in content.split(separator: "\n") {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                continue
            }

            switch type {
            case "result":
                state = .completed
            case "system":
                if object["status"] as? String == "requesting" {
                    state = .running
                }
            case "assistant":
                guard let message = object["message"] as? [String: Any] else {
                    continue
                }
                if message["stop_reason"] is String {
                    state = .completed
                } else {
                    state = .running
                }
            default:
                continue
            }
        }

        return state
    }

    private func auditURL(for metadataURL: URL) -> URL {
        metadataURL
            .deletingPathExtension()
            .appendingPathComponent("audit.jsonl")
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

    private func dateFromMilliseconds(_ value: Any?) -> Date? {
        if let value = value as? Double {
            return Date(timeIntervalSince1970: value / 1000)
        }

        if let value = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
        }

        return nil
    }

    private func summary(kind: ClaudeDesktopSessionKind, status: AgentTaskStatus, cwd: String?) -> String {
        let location = cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nilIfEmpty }
        let prefix: String
        switch (kind, status) {
        case (.cowork, .running):
            prefix = "Claude Desktop Cowork 正在处理"
        case (.code, .running):
            prefix = "Claude Desktop Code 正在处理"
        case (.cowork, .interrupted):
            prefix = "Claude Desktop Cowork 已中断"
        case (.code, .interrupted):
            prefix = "Claude Desktop Code 已中断"
        case (.cowork, _):
            prefix = "Claude Desktop Cowork 最近活动"
        case (.code, _):
            prefix = "Claude Desktop Code 最近活动"
        }

        return location.map { "\(prefix)：\($0)" } ?? prefix
    }
}

private enum ClaudeDesktopSessionKind: String {
    case cowork
    case code

    var defaultTitle: String {
        switch self {
        case .cowork: "Claude Desktop Cowork 会话"
        case .code: "Claude Desktop Code 会话"
        }
    }
}

private enum ClaudeDesktopAuditState {
    case unknown
    case running
    case completed
}
