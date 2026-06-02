import Foundation

enum AgentProviderID: String, CaseIterable, Codable, Sendable {
    case codex
    case chatGPT = "chatgpt"
    case claudeCLI = "claude-cli"
    case claudeDesktop = "claude-desktop"
    case hermes
    case openClaw = "openclaw"
    case traeCN = "trae-cn"
    case terminalAgents = "terminal-agents"
    case desktopApps = "desktop-apps"
}

struct AgentProviderDescriptor: Identifiable, Equatable, Sendable {
    let id: AgentProviderID
    var displayName: String
    var defaultEnabled: Bool
    var dataPaths: [String]
    var privacyDescription: String
    var detail: String

    static func defaults(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentProviderDescriptor] {
        let home = homeDirectory.path
        return [
            AgentProviderDescriptor(
                id: .codex,
                displayName: "Codex",
                defaultEnabled: true,
                dataPaths: [
                    "\(home)/.codex/session_index.jsonl",
                    "\(home)/.codex/sessions"
                ],
                privacyDescription: "Reads Codex thread titles, local paths, model, token usage, and task event metadata.",
                detail: "Reads local Codex session index and event streams."
            ),
            AgentProviderDescriptor(
                id: .chatGPT,
                displayName: "ChatGPT",
                defaultEnabled: true,
                dataPaths: [
                    "\(home)/Library/Application Support/com.openai.chat"
                ],
                privacyDescription: "Reads ChatGPT Desktop app running state, Accessibility button labels for generation state, and conversation cache modification times without parsing conversation text.",
                detail: "Observes ChatGPT Desktop running state and recent local cache activity."
            ),
            AgentProviderDescriptor(
                id: .claudeCLI,
                displayName: "Claude CLI",
                defaultEnabled: true,
                dataPaths: ["\(home)/.claude/projects"],
                privacyDescription: "Reads Claude local project session metadata, titles, paths, model, and token usage.",
                detail: "Reads local Claude project JSONL sessions."
            ),
            AgentProviderDescriptor(
                id: .claudeDesktop,
                displayName: "Claude Desktop",
                defaultEnabled: true,
                dataPaths: [
                    "\(home)/Library/Application Support/Claude-3p/local-agent-mode-sessions",
                    "\(home)/Library/Application Support/Claude-3p/claude-code-sessions"
                ],
                privacyDescription: "Reads Claude Desktop local-agent metadata and correlates active sessions with resume processes.",
                detail: "Reads Claude Desktop local agent session metadata."
            ),
            AgentProviderDescriptor(
                id: .hermes,
                displayName: "Hermes",
                defaultEnabled: true,
                dataPaths: ["\(home)/.hermes/state.db"],
                privacyDescription: "Reads Hermes local session database fields such as title, source, model, timestamps, and token usage.",
                detail: "Reads Hermes local state database."
            ),
            AgentProviderDescriptor(
                id: .openClaw,
                displayName: "OpenClaw",
                defaultEnabled: true,
                dataPaths: ["\(home)/.openclaw/agents"],
                privacyDescription: "Reads OpenClaw local session metadata, trajectory events, model, timestamps, and token usage.",
                detail: "Reads OpenClaw local session and trajectory files."
            ),
            AgentProviderDescriptor(
                id: .traeCN,
                displayName: "Trae CN",
                defaultEnabled: true,
                dataPaths: ["\(home)/Library/Application Support/Trae CN/logs"],
                privacyDescription: "Reads Trae CN ai-agent log timestamps and session/task identifiers without parsing conversation text.",
                detail: "Reads Trae CN ai-agent log metadata."
            ),
            AgentProviderDescriptor(
                id: .terminalAgents,
                displayName: "Terminal Agents",
                defaultEnabled: true,
                dataPaths: [],
                privacyDescription: "Reads local process command metadata from ps to detect running terminal agents.",
                detail: "Inspects local process metadata from ps."
            ),
            AgentProviderDescriptor(
                id: .desktopApps,
                displayName: "Desktop Apps",
                defaultEnabled: true,
                dataPaths: [],
                privacyDescription: "Reads running macOS application bundle identifiers for supported desktop apps.",
                detail: "Observes supported running macOS app bundle identifiers."
            )
        ]
    }
}

struct AgentProviderSetting: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var displayName: String
    var detail: String
    var isEnabled: Bool
}

enum ProviderDiagnosticStatus: String, Codable, Sendable {
    case ok
    case disabled
    case noData
    case missingPath
    case failed

    var title: String {
        switch self {
        case .ok: "OK"
        case .disabled: "Disabled"
        case .noData: "No Data"
        case .missingPath: "Missing Path"
        case .failed: "Failed"
        }
    }
}

struct ProviderDiagnostic: Identifiable, Equatable, Sendable {
    let id: String
    var displayName: String
    var status: ProviderDiagnosticStatus
    var message: String
    var dataPaths: [String]
    var lastCheckedAt: Date?
}
