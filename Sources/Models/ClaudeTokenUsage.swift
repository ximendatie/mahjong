import Foundation

struct ClaudeTokenUsageSummary: Equatable, Sendable {
    var todayTokens: Int
    var weekTokens: Int
    var todaySessions: Int
    var weekSessions: Int
    var primaryModel: String?
    var observedAt: Date
}

// MARK: - Claude Usage Limit (computed from local session data)

struct ClaudeUsageLimitSummary: Equatable, Sendable {
    var sessionWindow: ClaudeUsageWindow
    var weeklyWindow: ClaudeUsageWindow
    var serviceTier: String?
    var observedAt: Date
}

struct ClaudeUsageWindow: Equatable, Sendable {
    /// Total tokens used in this window (input + output + cache)
    var tokens: Int
    /// Number of API turns in this window
    var turns: Int
    /// When the oldest entry in this window expires (rolling window start + duration)
    var resetsAt: Date

    var inputTokens: Int
    var outputTokens: Int
    var cacheTokens: Int
}
