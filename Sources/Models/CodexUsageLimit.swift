import Foundation

struct CodexUsageLimitSummary: Equatable, Sendable {
    var limitID: String?
    var limitName: String?
    var primary: CodexUsageLimit
    var secondary: CodexUsageLimit?
    var observedAt: Date
}

struct CodexUsageLimit: Equatable, Sendable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}
