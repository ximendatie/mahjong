import SwiftUI

struct SettingsView: View {
    @ObservedObject var taskStore: AgentTaskStore

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    settingsSection
                        .frame(minWidth: 420, maxWidth: 620, alignment: .topLeading)
                    diagnosticsSection
                        .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 22) {
                    settingsSection
                    diagnosticsSection
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "隐私与 Provider",
                subtitle: "控制 mahjong 可以读取哪些本地来源，以及共享屏幕时显示多少信息。"
            )

            PrivacyToggleRow(isEnabled: taskStore.isPrivacyModeEnabled) { isEnabled in
                taskStore.setPrivacyModeEnabled(isEnabled)
            }

            MenuBarToggleRow(isEnabled: taskStore.isMenuBarEnabled) { isEnabled in
                taskStore.setMenuBarEnabled(isEnabled)
            }

            LazyVGrid(columns: providerColumns, alignment: .leading, spacing: 10) {
                ForEach(taskStore.providerSettings) { setting in
                    ProviderToggleRow(setting: setting) { isEnabled in
                        taskStore.setProviderEnabled(id: setting.id, isEnabled: isEnabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                sectionHeader(
                    title: "Provider Diagnostics",
                    subtitle: "刷新后显示本地路径、运行态和最近读取结果。"
                )
                Spacer()
                Button {
                    taskStore.refreshNow()
                } label: {
                    Label("刷新诊断", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            LazyVStack(spacing: 8) {
                ForEach(taskStore.diagnostics) { diagnostic in
                    DiagnosticRow(diagnostic: diagnostic, isPrivacyModeEnabled: taskStore.isPrivacyModeEnabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var providerColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 10, alignment: .topLeading)
        ]
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MenuBarToggleRow: View {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("菜单栏模式")
                    .font(.system(size: 14, weight: .semibold))
                Text("在菜单栏显示运行数量，并提供打开 Board、刷新和退出入口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onChange($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct PrivacyToggleRow: View {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("隐私模式")
                    .font(.system(size: 14, weight: .semibold))
                Text("隐藏任务标题、摘要、模型和 token 数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onChange($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .center)
        .background(settingsRowBackground)
    }

    private var settingsRowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

struct ProviderToggleRow: View {
    let setting: AgentProviderSetting
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(setting.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(setting.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(
                get: { setting.isEnabled },
                set: { onChange($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct DiagnosticRow: View {
    let diagnostic: ProviderDiagnostic
    let isPrivacyModeEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                statusDot
                Text(diagnostic.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(diagnostic.status.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusColor.opacity(0.12)))
                Spacer()
                Text(lastCheckedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(diagnostic.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !diagnostic.dataPaths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displayPaths, id: \.self) { path in
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
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

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch diagnostic.status {
        case .ok: .green
        case .disabled: .secondary
        case .noData: .orange
        case .missingPath: .red
        case .failed: .red
        }
    }

    private var displayPaths: [String] {
        if isPrivacyModeEnabled {
            return diagnostic.dataPaths.map { path in
                let lastComponent = URL(fileURLWithPath: path).lastPathComponent
                return "~/.../\(lastComponent)"
            }
        }

        return diagnostic.dataPaths
    }

    private var lastCheckedText: String {
        guard let lastCheckedAt = diagnostic.lastCheckedAt else {
            return "not checked"
        }
        return Formatters.relative(lastCheckedAt)
    }
}
