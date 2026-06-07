import Foundation

struct ClaudeTokenUsageSummary: Equatable, Sendable {
    var todayTokens: Int
    var weekTokens: Int
    var todaySessions: Int
    var weekSessions: Int
    var primaryModel: String?
    var observedAt: Date
}
