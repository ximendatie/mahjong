import AppKit
import SwiftUI

struct TaskCardView: View {
    let task: AgentTask
    let isSelected: Bool
    let isPrivacyModeEnabled: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isPrivacyModeEnabled ? "Private \(task.agent) session" : task.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                        Text(isPrivacyModeEnabled ? "Details hidden by privacy mode" : task.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    TaskAgentIconBadgeView(task: task)
                }

                VStack(spacing: 5) {
                    metadataRow("Model", isPrivacyModeEnabled ? "Hidden" : task.model)
                    metadataRow("Tokens", isPrivacyModeEnabled ? "Hidden" : Formatters.tokens(task.tokenUsage))
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(task.status == .history ? 0.55 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch task.status {
        case .running: .cyan
        case .completed: .green
        case .interrupted: .orange
        case .history: .secondary.opacity(0.45)
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption2)
    }
}

struct TaskAgentIconBadgeView: View {
    let task: AgentTask

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))

            if let image = AgentTaskIconResolver.image(for: task) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(Text("\(task.agent) icon"))
    }

    private var fallbackSystemImage: String {
        switch AgentTaskIconResolver.kind(for: task) {
        case .chatGPT: "bubble.left.and.bubble.right"
        case .codex: "sparkles"
        case .claude: "brain.head.profile"
        case .hermes: "bolt.circle"
        case .openClaw: "terminal"
        case .unknown: "cpu"
        }
    }

    private var fallbackColor: Color {
        switch AgentTaskIconResolver.kind(for: task) {
        case .chatGPT: .green
        case .codex: .cyan
        case .claude: .orange
        case .hermes: .purple
        case .openClaw: .blue
        case .unknown: .secondary
        }
    }
}

@MainActor
enum AgentTaskIconResolver {
    enum AgentKind {
        case chatGPT
        case codex
        case claude
        case hermes
        case openClaw
        case unknown
    }

    static func image(for task: AgentTask) -> NSImage? {
        if kind(for: task) == .hermes,
           let resourceURL = Bundle.main.url(forResource: "AgentIcons/hermes", withExtension: "png") {
            return NSImage(contentsOf: resourceURL)
        }

        guard let bundleIdentifier = bundleIdentifier(for: task) else {
            return nil
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    static func kind(for task: AgentTask) -> AgentKind {
        let lowercased = task.agent.lowercased()

        if lowercased.contains("chatgpt") {
            return .chatGPT
        }

        if lowercased.contains("codex") {
            return .codex
        }

        if lowercased.contains("claude") {
            return .claude
        }

        if lowercased.contains("hermes") {
            return .hermes
        }

        if lowercased.contains("openclaw") {
            return .openClaw
        }

        return .unknown
    }

    private static func bundleIdentifier(for task: AgentTask) -> String? {
        switch kind(for: task) {
        case .chatGPT:
            return AgentRuntimeIconBundle.chatGPT
        case .codex:
            return AgentRuntimeIconBundle.codex
        case .claude:
            return AgentRuntimeIconBundle.claude
        case .hermes:
            return AgentRuntimeIconBundle.hermes
        case .openClaw:
            return AgentRuntimeIconBundle.openClaw
        case .unknown:
            return nil
        }
    }
}
