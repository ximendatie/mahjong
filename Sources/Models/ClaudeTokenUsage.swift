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

// MARK: - Estimated usage budget (configurable)

/// Claude does not write rate-limit data locally — only token counts. To show a
/// percentage like Claude.ai's "42% used", we estimate against a configurable token
/// ceiling. Defaults are calibrated so a typical Pro-plan session matches the app's
/// reading; users can override both values in Settings.
enum ClaudeUsageBudget {
    static let sessionKey = "claudeSessionTokenLimit"
    static let weeklyKey = "claudeWeeklyTokenLimit"

    /// ~32M tokens ≈ 42% of a Pro 5-hour session (reverse-engineered from Claude.ai).
    static let defaultSession = 76_700_000
    /// ~32M tokens ≈ 5% of a Pro weekly all-models limit.
    static let defaultWeekly = 644_000_000
}
