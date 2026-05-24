import AppKit
import SwiftUI

struct BoardView: View {
    @ObservedObject var taskStore: AgentTaskStore
    @State private var selectedTab = BoardTab.sessions
    @State private var selectedTaskID: String?
    @State private var showsArchivedTasks = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                BoardSidebarView(selectedTab: $selectedTab)
                Divider()
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 420)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Board")
                    .font(.title3.weight(.semibold))
                Text("全局 Agent 运行状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            runningBadge
            runtimeBadge

            Button {
                taskStore.refreshNow()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            if selectedTab == .sessions {
                Button {
                    taskStore.completeTask(id: selectedTaskID)
                } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .disabled(taskStore.task(id: selectedTaskID)?.status != .running)

                Button {
                    taskStore.archiveTask(id: selectedTaskID)
                } label: {
                    Label("归档", systemImage: "archivebox")
                }
                .disabled(taskStore.task(id: selectedTaskID)?.status == nil || taskStore.task(id: selectedTaskID)?.status == .running)

                Button {
                    showsArchivedTasks.toggle()
                } label: {
                    Label(showsArchivedTasks ? "隐藏归档" : "显示归档", systemImage: showsArchivedTasks ? "eye.slash" : "eye")
                }
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var runningBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(taskStore.isWorking ? Color.cyan : Color.secondary.opacity(0.45))
                .frame(width: 8, height: 8)
            Text("\(taskStore.runningCount) running")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private var runtimeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(taskStore.runningAgentCount) agents")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private var columns: some View {
        HStack(spacing: 0) {
            TaskColumnView(status: .running, tasks: taskStore.tasks(for: .running), selectedTaskID: $selectedTaskID)
            Divider()
            TaskColumnView(status: .completed, tasks: taskStore.tasks(for: .completed), selectedTaskID: $selectedTaskID)
            if showsArchivedTasks {
                Divider()
                TaskColumnView(status: .history, tasks: taskStore.tasks(for: .history), selectedTaskID: $selectedTaskID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .sessions:
            columns
        case .agents:
            AgentRuntimeListView(runtimes: taskStore.runtimes)
        case .futureTasks:
            FutureTasksView(taskStore: taskStore)
        }
    }
}

private enum BoardTab: String, CaseIterable, Identifiable {
    case sessions
    case agents
    case futureTasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Session 任务"
        case .agents: "运行 Agent"
        case .futureTasks: "未来任务"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions: "rectangle.3.group"
        case .agents: "cpu"
        case .futureTasks: "calendar.badge.plus"
        }
    }
}

private struct BoardSidebarView: View {
    @Binding var selectedTab: BoardTab

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("视图")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 16)

            VStack(spacing: 6) {
                ForEach(BoardTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 18)
                            Text(tab.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 176, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035))
    }
}

private struct TaskColumnView: View {
    let status: AgentTaskStatus
    let tasks: [AgentTask]
    @Binding var selectedTaskID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(status.title)
                    .font(.headline)
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        TaskCardView(task: task, isSelected: selectedTaskID == task.id)
                            .onTapGesture(count: 2) {
                                selectedTaskID = task.id
                                OpenTargetHandler.open(task)
                            }
                            .onTapGesture {
                                selectedTaskID = task.id
                            }
                    }

                    if tasks.isEmpty {
                        EmptyColumnView(status: status)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct TaskCardView: View {
    let task: AgentTask
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Text(task.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(spacing: 5) {
                    metadataRow("Agent", task.agent)
                    metadataRow("Model", task.model)
                    metadataRow("Tokens", Formatters.tokens(task.tokenUsage))
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

private struct EmptyColumnView: View {
    let status: AgentTaskStatus

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("暂无\(status.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var iconName: String {
        switch status {
        case .running: "pause.circle"
        case .completed: "checkmark.circle"
        case .history: "clock"
        }
    }
}

private struct AgentRuntimeListView: View {
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

@MainActor
private enum OpenTargetHandler {
    static func open(_ task: AgentTask) {
        if let openURL = task.openURL {
            NSWorkspace.shared.open(openURL)
            return
        }

        activateApp(named: task.agent)
    }

    static func open(_ runtime: AgentRuntime) {
        if let bundleIdentifier = runtime.bundleIdentifier {
            activateApp(bundleIdentifier: bundleIdentifier)
            return
        }

        activateApp(named: runtime.provider)
    }

    private static func activateApp(bundleIdentifier: String) {
        let runningApp = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier
        }
        runningApp?.activate(options: [.activateIgnoringOtherApps])
    }

    private static func activateApp(named name: String) {
        let lowercasedName = name.lowercased()
        let runningApp = NSWorkspace.shared.runningApplications.first { app in
            app.localizedName?.lowercased().contains(lowercasedName) == true
        }
        runningApp?.activate(options: [.activateIgnoringOtherApps])
    }
}

private struct FutureTasksView: View {
    @ObservedObject var taskStore: AgentTaskStore
    @State private var selectedAgent: FutureAgent = .codex
    @State private var title = ""
    @State private var prompt = ""
    @State private var modelHint = ""
    @State private var scheduledAt = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()

    var body: some View {
        VStack(spacing: 0) {
            agentTabs
            Divider()

            HStack(spacing: 0) {
                createForm
                    .frame(width: 320)
                Divider()
                futureTaskList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var agentTabs: some View {
        HStack(spacing: 8) {
            ForEach(FutureAgent.allCases) { agent in
                Button {
                    selectedAgent = agent
                    if modelHint.isEmpty {
                        modelHint = agent.modelPlaceholder
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: agent.systemImage)
                            .frame(width: 16)
                        Text(agent.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .foregroundStyle(selectedAgent == agent ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedAgent == agent ? Color.accentColor : Color.primary.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .onAppear {
            if modelHint.isEmpty {
                modelHint = selectedAgent.modelPlaceholder
            }
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("创建 \(selectedAgent.title) 任务")
                    .font(.headline)
                Text("仅保存到 AgentsPet 本地计划列表")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("标题")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例如：整理本周 Agent 进展", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("任务内容")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 118)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("模型提示")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(selectedAgent.modelPlaceholder, text: $modelHint)
                    .textFieldStyle(.roundedBorder)
            }

            DatePicker("计划时间", selection: $scheduledAt, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)

            Button {
                taskStore.createFutureTask(
                    title: title,
                    prompt: prompt,
                    agent: selectedAgent,
                    modelHint: modelHint,
                    scheduledAt: scheduledAt
                )
                resetForm()
            } label: {
                Label("创建任务", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.025))
    }

    private var futureTaskList: some View {
        let tasks = taskStore.futureTasks(for: selectedAgent)

        return ScrollView {
            LazyVStack(spacing: 10) {
                HStack {
                    Text("\(selectedAgent.title) 未来任务")
                        .font(.headline)
                    Spacer()
                    Text("\(tasks.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 24)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .padding(.bottom, 2)

                ForEach(tasks) { task in
                    FutureTaskCardView(task: task) {
                        taskStore.deleteFutureTask(id: task.id)
                    }
                }

                if tasks.isEmpty {
                    EmptyFutureTasksView(agent: selectedAgent)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func resetForm() {
        title = ""
        prompt = ""
        modelHint = selectedAgent.modelPlaceholder
        scheduledAt = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    }
}

private struct FutureTaskCardView: View {
    let task: FutureAgentTask
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: task.agent.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除未来任务")
                }

                Text(task.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                VStack(spacing: 5) {
                    metadataRow("Agent", task.agent.title)
                    metadataRow("Model", task.modelHint.isEmpty ? task.agent.modelPlaceholder : task.modelHint)
                    metadataRow("Scheduled", Self.scheduleFormatter.string(from: task.scheduledAt))
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

    private static let scheduleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct EmptyFutureTasksView: View {
    let agent: FutureAgent

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("暂无 \(agent.title) 未来任务")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}

private struct AgentRuntimeCardView: View {
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

private struct AgentRuntimeIconView: View {
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
private enum AgentRuntimeIconResolver {
    static func image(for runtime: AgentRuntime) -> NSImage? {
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
