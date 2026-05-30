import AppKit
import SwiftUI

struct AgentRuntimeListView: View {
    let runtimes: [AgentRuntime]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(runtimes) { runtime in
                    AgentRuntimeCardView(runtime: runtime)
                        .onTapGesture(count: 2) {
                            OpenTargetHandler.open(runtime)
                        }
                }

                if runtimes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "power")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("暂无运行中的 Agent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 72)
                    .gridCellColumns(2)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 260), spacing: 12),
            GridItem(.flexible(minimum: 260), spacing: 12)
        ]
    }
}

struct AgentRuntimeCardView: View {
    let runtime: AgentRuntime

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                AgentRuntimeIconView(runtime: runtime)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(runtime.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(runtime.kind.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }

                    Text(runtime.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(spacing: 5) {
                    metadataRow("Provider", runtime.provider)
                    metadataRow("Processes", "\(runtime.processCount)")
                    metadataRow("Updated", Formatters.relative(runtime.updatedAt))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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
