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

        var sessionID = url.deletingPathExtension().lastPathComponent
        var title: String?
        var cwd: String?
        var model: String?
        var totalTokens = 0
        var lastTimestamp: Date?
        var lastSpeaker: String?

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
        }

        let updatedAt = lastTimestamp ?? Date.distantPast
        let isRecent = Date().timeIntervalSince(updatedAt) < 15 * 60
        let status: AgentTaskStatus = isRecent && lastSpeaker == "user" ? .running : (Date().timeIntervalSince(updatedAt) < 24 * 60 * 60 ? .completed : .history)
        let folderName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude 会话"

        return AgentTask(
            id: "claude:\(sessionID)",
            title: title ?? folderName,
            summary: status == .running ? "Claude 本机会话最近有用户输入，可能正在处理" : "Claude 本机会话最近活动",
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
