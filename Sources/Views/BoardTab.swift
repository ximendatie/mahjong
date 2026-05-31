enum BoardTab: String, CaseIterable, Identifiable {
    case sessions
    case agents
    case tokenUsage
    case futureTasks
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Session 任务"
        case .agents: "运行 Agent"
        case .tokenUsage: "Token 统计"
        case .futureTasks: "未来计划"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions: "rectangle.3.group"
        case .agents: "cpu"
        case .tokenUsage: "chart.bar.xaxis"
        case .futureTasks: "calendar.badge.plus"
        case .settings: "switch.2"
        }
    }
}
