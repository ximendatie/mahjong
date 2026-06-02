import Foundation

struct TraeCNLocalProvider: AgentTaskProvider {
    let providerID = AgentProviderID.traeCN
    let providerName = "Trae CN"

    private static let recentActivityWindow: TimeInterval = 24 * 60 * 60
    private static let runningActivityWindow: TimeInterval = 10 * 60
    private static let maxLogBytes = 1024 * 1024
    private let logsDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        logsDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Trae CN", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    func fetchTasks() async -> [AgentTask] {
        await Task.detached(priority: .utility) {
            readTasks()
        }.value
    }

    private func readTasks(now: Date = Date()) -> [AgentTask] {
        var sessionsByID: [String: TraeCNLogSession] = [:]

        for logURL in findAgentLogFiles() {
            for line in readTailLines(from: logURL) {
                guard let event = Self.event(from: line) else {
                    continue
                }

                var session = sessionsByID[event.sessionID] ?? TraeCNLogSession(
                    id: event.sessionID,
                    taskID: nil,
                    startedAt: event.timestamp,
                    updatedAt: event.timestamp
                )
                session.taskID = event.taskID ?? session.taskID
                session.startedAt = min(session.startedAt, event.timestamp)
                session.updatedAt = max(session.updatedAt, event.timestamp)
                sessionsByID[event.sessionID] = session
            }
        }

        return sessionsByID.values
            .filter { now.timeIntervalSince($0.updatedAt) < Self.recentActivityWindow }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map { session in
                let status: AgentTaskStatus = now.timeIntervalSince(session.updatedAt) < Self.runningActivityWindow
                    ? .running
                    : .completed
                return AgentTask(
                    id: "trae-cn:\(session.id)",
                    title: "Trae CN 会话 \(session.id.prefix(8))",
                    summary: summary(for: session, status: status),
                    agent: "Trae CN",
                    providerID: providerID,
                    model: "unknown",
                    tokenUsage: 0,
                    status: status,
                    updatedAt: session.updatedAt
                )
            }
    }

    private func findAgentLogFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.lastPathComponent.hasPrefix("ai-agent_"),
                  url.lastPathComponent.hasSuffix("_stdout.log")
            else {
                return nil
            }
            return url
        }
        .sorted { lhs, rhs in
            modificationDate(for: lhs) > modificationDate(for: rhs)
        }
        .prefix(4)
        .map { $0 }
    }

    private func readTailLines(from url: URL) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return []
        }
        defer {
            try? handle.close()
        }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(Self.maxLogBytes) ? size - UInt64(Self.maxLogBytes) : 0
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            guard let content = String(data: data, encoding: .utf8) else {
                return []
            }
            return content.split(separator: "\n")
        } catch {
            return []
        }
    }

    private func summary(for session: TraeCNLogSession, status: AgentTaskStatus) -> String {
        let statusText = status == .running ? "检测到近期 ai-agent 活动" : "检测到最近 ai-agent 活动"
        if let taskID = session.taskID {
            return "\(statusText)；task \(taskID.prefix(8))；不读取对话正文"
        }
        return "\(statusText)；不读取对话正文"
    }

    static func event(from line: Substring) -> TraeCNLogEvent? {
        guard let timestamp = timestamp(from: line),
              line.contains("session_id="),
              let sessionID = firstMatch(in: line, pattern: #"session_id=([0-9a-f]{24})"#)
        else {
            return nil
        }

        return TraeCNLogEvent(
            sessionID: sessionID,
            taskID: firstMatch(in: line, pattern: #"task_id=([0-9a-f]{24})"#),
            timestamp: timestamp
        )
    }

    private static func timestamp(from line: Substring) -> Date? {
        guard let firstSpace = line.firstIndex(of: " ") else {
            return nil
        }
        return parseDate(String(line[..<firstSpace]))
    }

    private static func firstMatch(in line: Substring, pattern: String) -> String? {
        let string = String(line)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: string,
                range: NSRange(string.startIndex..., in: string)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string)
        else {
            return nil
        }
        return String(string[range])
    }
}

struct TraeCNLogEvent {
    var sessionID: String
    var taskID: String?
    var timestamp: Date
}

struct TraeCNLogSession {
    var id: String
    var taskID: String?
    var startedAt: Date
    var updatedAt: Date
}

private func modificationDate(for url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
}
