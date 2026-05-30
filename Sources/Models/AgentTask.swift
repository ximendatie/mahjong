import Foundation

enum AgentTaskStatus: String, CaseIterable, Identifiable, Sendable {
    case running
    case completed
    case interrupted
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: "进行中"
        case .completed: "已完成"
        case .interrupted: "已中断"
        case .history: "已归档"
        }
    }
}

struct AgentTask: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var summary: String
    var agent: String
    var providerID: AgentProviderID?
    var model: String
    var tokenUsage: Int
    var status: AgentTaskStatus
    var updatedAt: Date
    var openURL: URL?

    init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        agent: String,
        providerID: AgentProviderID? = nil,
        model: String,
        tokenUsage: Int,
        status: AgentTaskStatus,
        updatedAt: Date = Date(),
        openURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.agent = agent
        self.providerID = providerID
        self.model = model
        self.tokenUsage = tokenUsage
        self.status = status
        self.updatedAt = updatedAt
        self.openURL = openURL
    }
}
