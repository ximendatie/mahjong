import Foundation

enum TokenUsageTimeRange: String, CaseIterable, Identifiable {
    case all
    case lastMonth
    case today

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "所有记录"
        case .lastMonth: "近一个月"
        case .today: "今天"
        }
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .lastMonth:
            guard let start = calendar.date(byAdding: .month, value: -1, to: now) else {
                return true
            }
            return date >= start && date <= now
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        }
    }
}

struct TokenUsageSummary: Identifiable, Equatable, Sendable {
    var id: String { providerID?.rawValue ?? agent }
    var agent: String
    var providerID: AgentProviderID?
    var taskCount: Int
    var totalTokens: Int
    var latestActivityAt: Date
}
