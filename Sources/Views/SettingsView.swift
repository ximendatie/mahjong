import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var taskStore: AgentTaskStore
    @StateObject private var versionChecker = AppVersionChecker()

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    controlsColumn
                        .frame(minWidth: 360, maxWidth: 460, alignment: .topLeading)
                    diagnosticsSection
                        .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    controlsColumn
                    diagnosticsSection
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            generalSection
            claudeBudgetSection
            versionSection
            providersSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var claudeBudgetSection: some View {
        SettingsGroupBox(
            title: "Claude 估算额度",
            subtitle: "Claude 不在本地写入配额，Token 统计页的消耗百分比按这里的额度估算。"
        ) {
            ClaudeBudgetEditor()
        }
    }

    private var generalSection: some View {
        SettingsGroupBox(
            title: "通用",
            subtitle: "控制 mahjong 的显示方式和共享屏幕时暴露的信息。"
        ) {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "隐私模式",
                    subtitle: "隐藏任务标题、摘要、模型和 token 数。",
                    systemImage: "eye.slash",
                    isEnabled: taskStore.isPrivacyModeEnabled
                ) { isEnabled in
                    taskStore.setPrivacyModeEnabled(isEnabled)
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: "菜单栏模式",
                    subtitle: "在菜单栏显示运行数量，并提供打开 Board、刷新和退出入口。",
                    systemImage: "menubar.rectangle",
                    isEnabled: taskStore.isMenuBarEnabled
                ) { isEnabled in
                    taskStore.setMenuBarEnabled(isEnabled)
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: "Dock 图标",
                    subtitle: "显示 Dock 入口；关闭后保留菜单栏和桌宠入口。",
                    systemImage: "dock.rectangle",
                    isEnabled: taskStore.isDockIconEnabled
                ) { isEnabled in
                    taskStore.setDockIconEnabled(isEnabled)
                }
            }
        }
    }

    private var versionSection: some View {
        SettingsGroupBox(
            title: "版本",
            subtitle: "手动检查 GitHub Release 上的新版本。"
        ) {
            VersionUpdateRow(versionChecker: versionChecker)
        }
    }

    private var providersSection: some View {
        SettingsGroupBox(
            title: "Provider",
            subtitle: "选择 mahjong 可以读取哪些本地来源。"
        ) {
            LazyVGrid(columns: providerColumns, alignment: .leading, spacing: 10) {
                ForEach(taskStore.providerSettings) { setting in
                    ProviderToggleRow(setting: setting) { isEnabled in
                        taskStore.setProviderEnabled(id: setting.id, isEnabled: isEnabled)
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        SettingsGroupBox(
            title: "Provider Diagnostics",
            subtitle: "刷新后显示本地路径、运行态和最近读取结果。"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var providerColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 10, alignment: .topLeading)
        ]
    }
}

struct SettingsGroupBox<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content
                .padding(.top, 9)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(settingsCardBackground)
    }
}

struct VersionUpdateRow: View {
    @ObservedObject var versionChecker: AppVersionChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("当前版本")
                    .font(.system(size: 13, weight: .semibold))
                Text("v\(versionChecker.currentVersion)")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if case let .updateAvailable(_, _, releaseURL) = versionChecker.status {
                    Button {
                        NSWorkspace.shared.open(releaseURL)
                    } label: {
                        Label("下载更新", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    versionChecker.checkForUpdates()
                } label: {
                    if versionChecker.status == .checking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("检查更新", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(versionChecker.status == .checking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        switch versionChecker.status {
        case .idle:
            "手动检查 GitHub Release；发现新版本后打开下载页面。"
        case .checking:
            "正在检查最新版本..."
        case let .upToDate(version):
            "当前已是最新版本 v\(version)。"
        case let .updateAvailable(_, latestVersion, _):
            "发现新版本 v\(latestVersion)，可打开 Release 页面下载。"
        case let .failed(message):
            "\(message) 可点击“检查更新”重试。"
        }
    }

    private var statusColor: Color {
        switch versionChecker.status {
        case .failed:
            .red
        case .updateAvailable:
            .green
        default:
            .secondary
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
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
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 32)
    }
}

struct ProviderToggleRow: View {
    let setting: AgentProviderSetting
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(setting.displayName)
                    .font(.system(size: 13, weight: .semibold))
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
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ClaudeBudgetEditor: View {
    @AppStorage(ClaudeUsageBudget.sessionKey) private var sessionLimit = ClaudeUsageBudget.defaultSession
    @AppStorage(ClaudeUsageBudget.weeklyKey) private var weeklyLimit = ClaudeUsageBudget.defaultWeekly

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field(
                title: "会话额度",
                subtitle: "5 小时滚动窗口的 token 上限",
                value: $sessionLimit
            )
            SettingsDivider()
            field(
                title: "每周额度",
                subtitle: "7 天窗口的 token 上限",
                value: $weeklyLimit
            )

            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("默认值由 Claude.ai 当前读数反推，仅供参考。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Button("恢复默认") {
                    sessionLimit = ClaudeUsageBudget.defaultSession
                    weeklyLimit = ClaudeUsageBudget.defaultWeekly
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.top, 8)
        }
    }

    private func field(title: String, subtitle: String, value: Binding<Int>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            HStack(spacing: 5) {
                TextField(
                    "",
                    value: millionsBinding(value),
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 74)
                Text("M tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    private func millionsBinding(_ value: Binding<Int>) -> Binding<Double> {
        Binding(
            get: { Double(value.wrappedValue) / 1_000_000 },
            set: { value.wrappedValue = max(1_000_000, Int(($0 * 1_000_000).rounded())) }
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

            if isChatGPTAccessibilityIssue {
                Button {
                    openAccessibilitySettings()
                } label: {
                    Label("打开辅助功能设置", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(settingsCardBackground)
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

    private var isChatGPTAccessibilityIssue: Bool {
        diagnostic.id == AgentProviderID.chatGPT.rawValue && diagnostic.status == .failed
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private var settingsCardBackground: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
}
