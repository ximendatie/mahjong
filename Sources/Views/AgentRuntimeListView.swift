import AppKit
import SwiftUI

struct AgentRuntimeListView: View {
    let runtimes: [AgentRuntime]
    var tokensByProvider: [String: Int] = [:]

    private var groups: [(kind: AgentRuntimeKind, runtimes: [AgentRuntime])] {
        let order: [AgentRuntimeKind] = [.terminal, .desktopApp]
        return order.compactMap { kind in
            let items = runtimes
                .filter { $0.kind == kind }
                .sorted { $0.updatedAt > $1.updatedAt }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    var body: some View {
        ScrollView {
            if runtimes.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups, id: \.kind) { group in
                        section(for: group.kind, runtimes: group.runtimes)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section(for kind: AgentRuntimeKind, runtimes: [AgentRuntime]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: kind == .terminal ? "terminal" : "macwindow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(runtimes.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(runtimes) { runtime in
                    AgentRuntimeCardView(runtime: runtime, tokens: tokens(for: runtime))
                        .onTapGesture(count: 2) {
                            OpenTargetHandler.open(runtime)
                        }
                }
            }
        }
    }

    private func tokens(for runtime: AgentRuntime) -> Int? {
        tokensByProvider[runtime.provider.lowercased()]
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "power")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("暂无运行中的 Agent")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12, alignment: .topLeading)
        ]
    }
}

struct AgentRuntimeCardView: View {
    let runtime: AgentRuntime
    var tokens: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                AgentRuntimeIconView(runtime: runtime)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(runtime.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("运行中")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(runtime.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if let tokens, tokens > 0 {
                        metaChip(systemImage: "number", text: Formatters.tokens(tokens))
                    }
                    metaChip(systemImage: "clock", text: Formatters.relative(runtime.updatedAt))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
    }

    private func metaChip(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct AgentRuntimeIconView: View {
    let runtime: AgentRuntime

    var body: some View {
        if let image = AgentRuntimeIconResolver.image(for: runtime) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(5)
                .accessibilityLabel(Text("\(runtime.provider) icon"))
        } else {
            Image(systemName: runtime.kind == .terminal ? "terminal" : "app.dashed")
                .font(.title3)
                .foregroundStyle(fallbackColor)
                .accessibilityLabel(Text("\(runtime.provider) icon"))
        }
    }

    private var fallbackColor: Color {
        switch runtime.kind {
        case .desktopApp: .blue
        case .terminal: .cyan
        }
    }
}

@MainActor
enum AgentRuntimeIconResolver {
    static func image(for runtime: AgentRuntime) -> NSImage? {
        if let iconResourceName = runtime.iconResourceName,
           let resourceURL = Bundle.main.url(forResource: iconResourceName, withExtension: "png") {
            return NSImage(contentsOf: resourceURL)
        }

        let bundleIdentifiers = [
            runtime.bundleIdentifier,
            runtime.iconBundleIdentifier
        ].compactMap(\.self)

        for bundleIdentifier in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return NSWorkspace.shared.icon(forFile: appURL.path)
            }
        }

        return nil
    }
}
