import Foundation

struct OpenClawLocalProvider: AgentTaskProvider {
    let providerID = AgentProviderID.openClaw
    let providerName = "OpenClaw"

    private static let recentActivityWindow: TimeInterval = 24 * 60 * 60
    private static let runningActivityWindow: TimeInterval = 10 * 60
    private let agentsDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        agentsDirectory = homeDirectory
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
    }

    func fetchTasks() async -> [AgentTask] {
        await Task.detached(priority: .utility) {
            readTasks()
        }.value
    }

    private func readTasks() -> [AgentTask] {
        findSessionFiles().compactMap(readTask(from:))
    }

    private func readTask(from sessionURL: URL) -> AgentTask? {
        let messages = readMessages(from: sessionURL)
        guard !messages.isEmpty else {
            return nil
        }

        let sessionID = sessionURL.deletingPathExtension().lastPathComponent
        let trajectoryURL = sessionURL
            .deletingPathExtension()
            .appendingPathExtension("trajectory.jsonl")
        let trajectory = readTrajectory(from: trajectoryURL)
        let latestUserMessage = messages.last { $0.role == "user" && isVisibleUserText($0.text) }
        guard latestUserMessage != nil || trajectory.runs.contains(where: { $0.isInternal == false }) else {
            return nil
        }
        let latestAssistantMessage = messages.last { $0.role == "assistant" && $0.isDeliveryMirror == false }
        let updatedAt = max(
            messages.compactMap(\.timestamp).max() ?? Date.distantPast,
            trajectory.updatedAt ?? Date.distantPast
        )
        let status = status(for: trajectory, updatedAt: updatedAt)

        return AgentTask(
            id: "openclaw:\(sessionID)",
            title: title(from: latestUserMessage?.text),
            summary: summary(status: status, workspaceDirectory: trajectory.workspaceDirectory),
            agent: "OpenClaw",
            providerID: providerID,
            model: latestAssistantMessage?.model ?? trajectory.model ?? "unknown",
            tokenUsage: messages.map(\.tokenUsage).max() ?? 0,
            status: status,
            updatedAt: updatedAt,
            openURL: sessionURL
        )
    }

    private func findSessionFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: agentsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard
                let url = item as? URL,
                url.pathExtension == "jsonl",
                !url.lastPathComponent.contains(".trajectory")
            else {
                return nil
            }
            return url
        }
    }

    private func readMessages(from url: URL) -> [OpenClawSessionMessage] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return content.split(separator: "\n").compactMap { line in
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["type"] as? String == "message",
                let message = object["message"] as? [String: Any],
                let role = message["role"] as? String
            else {
                return nil
            }

            return OpenClawSessionMessage(
                role: role,
                text: messageText(from: message["content"]),
                timestamp: parseDate(object["timestamp"] as? String)
                    ?? dateFromMilliseconds(message["timestamp"])
                    ?? Date.distantPast,
                model: displayModel(from: message["model"] as? String),
                isDeliveryMirror: isDeliveryMirror(message: message),
                tokenUsage: tokenUsage(from: message["usage"])
            )
        }
    }

    private func readTrajectory(from url: URL) -> OpenClawTrajectoryState {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return OpenClawTrajectoryState()
        }

        var runByID: [String: OpenClawTrajectoryRun] = [:]
        var updatedAt: Date?
        var workspaceDirectory: String?
        var model: String?
        for line in content.split(separator: "\n") {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String
            else {
                continue
            }

            let eventAt = parseDate(object["ts"] as? String) ?? Date.distantPast
            updatedAt = max(updatedAt ?? eventAt, eventAt)
            workspaceDirectory = (object["workspaceDir"] as? String)?.nilIfEmpty ?? workspaceDirectory
            model = (object["modelId"] as? String)?.nilIfEmpty ?? model
            guard let runID = object["runId"] as? String else {
                continue
            }

            var run = runByID[runID] ?? OpenClawTrajectoryRun(startedAt: eventAt, endedAt: nil, isInternal: false)
            if type == "session.started" {
                run.startedAt = eventAt
            }
            if type == "session.ended" {
                run.endedAt = eventAt
            }
            if isInternalEvent(object) {
                run.isInternal = true
            }
            runByID[runID] = run
        }

        return OpenClawTrajectoryState(
            runs: Array(runByID.values),
            updatedAt: updatedAt,
            workspaceDirectory: workspaceDirectory,
            model: model
        )
    }

    private func status(for trajectory: OpenClawTrajectoryState, updatedAt: Date) -> AgentTaskStatus {
        let now = Date()
        if trajectory.runs.contains(where: { run in
            run.endedAt == nil
                && run.isInternal == false
                && now.timeIntervalSince(max(run.startedAt, updatedAt)) < Self.runningActivityWindow
        }) {
            return .running
        }

        return Date().timeIntervalSince(updatedAt) < Self.recentActivityWindow ? .completed : .history
    }

    private func title(from text: String?) -> String {
        let trimmed = normalizedUserText(from: text)

        return trimmed ?? "OpenClaw 会话"
    }

    private func normalizedUserText(from text: String?) -> String? {
        text?
            .replacingOccurrences(of: #"(?s)^Sender \(untrusted metadata\):\s*```json.*?```\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\[[^\]]+\]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func isVisibleUserText(_ text: String?) -> Bool {
        guard let normalized = normalizedUserText(from: text) else {
            return false
        }
        return normalized != "[OpenClaw heartbeat poll]"
            && normalized.hasPrefix("Delivery: to send a message") == false
    }

    private func summary(status: AgentTaskStatus, workspaceDirectory: String?) -> String {
        let location = workspaceDirectory.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nilIfEmpty }
        let prefix = status == .running ? "OpenClaw 正在处理" : "OpenClaw 最近活动"
        return location.map { "\(prefix)：\($0)" } ?? prefix
    }

    private func messageText(from content: Any?) -> String? {
        if let content = content as? String {
            return content.nilIfEmpty
        }

        if let parts = content as? [[String: Any]] {
            let text = parts.compactMap { part -> String? in
                guard part["type"] as? String == "text" else {
                    return nil
                }
                return (part["text"] as? String)?.nilIfEmpty
            }.joined(separator: "\n")
            return text.nilIfEmpty
        }

        return nil
    }

    private func tokenUsage(from value: Any?) -> Int {
        guard let usage = value as? [String: Any] else {
            return 0
        }

        if let totalTokens = usage["totalTokens"] as? Int {
            return totalTokens
        }

        let keys = [
            "input",
            "output",
            "cacheRead",
            "cacheWrite"
        ]

        return keys.reduce(0) { partialResult, key in
            partialResult + (usage[key] as? Int ?? 0)
        }
    }

    private func displayModel(from value: String?) -> String? {
        guard value != "delivery-mirror" else {
            return nil
        }
        return value?.nilIfEmpty
    }

    private func isDeliveryMirror(message: [String: Any]) -> Bool {
        message["model"] as? String == "delivery-mirror"
    }

    private func isInternalEvent(_ object: [String: Any]) -> Bool {
        let sessionKey = object["sessionKey"] as? String
        let data = object["data"] as? [String: Any]

        return sessionKey?.contains(":heartbeat") == true
            || data?["trigger"] as? String == "heartbeat"
            || data?["messageProvider"] as? String == "heartbeat"
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
}

private struct OpenClawSessionMessage {
    var role: String
    var text: String?
    var timestamp: Date
    var model: String?
    var isDeliveryMirror: Bool
    var tokenUsage: Int
}

private struct OpenClawTrajectoryState {
    var runs: [OpenClawTrajectoryRun] = []
    var updatedAt: Date?
    var workspaceDirectory: String?
    var model: String?
}

private struct OpenClawTrajectoryRun {
    var startedAt: Date
    var endedAt: Date?
    var isInternal: Bool
}
