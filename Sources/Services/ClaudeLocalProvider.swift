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
