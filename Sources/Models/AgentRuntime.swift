import Foundation

enum AgentRuntimeKind: String, Sendable {
    case desktopApp
    case terminal

    var title: String {
        switch self {
        case .desktopApp: "桌面端"
        case .terminal: "终端"
        }
    }
}

struct AgentRuntime: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var provider: String
    var providerID: AgentProviderID?
    var kind: AgentRuntimeKind
    var summary: String
    var processCount: Int
    var updatedAt: Date
    var bundleIdentifier: String?
    var iconBundleIdentifier: String?
    var iconResourceName: String?

    init(
        id: String,
        name: String,
        provider: String,
        providerID: AgentProviderID? = nil,
        kind: AgentRuntimeKind,
        summary: String,
        processCount: Int = 1,
        updatedAt: Date = Date(),
        bundleIdentifier: String? = nil,
        iconBundleIdentifier: String? = nil,
        iconResourceName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.providerID = providerID
        self.kind = kind
        self.summary = summary
        self.processCount = processCount
        self.updatedAt = updatedAt
        self.bundleIdentifier = bundleIdentifier
        self.iconBundleIdentifier = iconBundleIdentifier
        self.iconResourceName = iconResourceName
    }
}
