import AppKit
import SwiftUI

struct BoardView: View {
    @ObservedObject var taskStore: AgentTaskStore
    @State private var selectedTab = BoardTab.sessions
    @State private var selectedTaskID: String?
    @State private var showsArchivedTasks = false
    @State private var showsArchivedFutureTasks = true

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
                Text("mahjong Board")
                    .font(.title3.weight(.semibold))
                Text("全局 Agent 运行状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            privacyBadge

            Button {
                taskStore.refreshNow()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            if selectedTab == .futureTasks {
                Button {
                    showsArchivedFutureTasks.toggle()
                } label: {
                    Label(
                        showsArchivedFutureTasks ? "隐藏归档" : "显示归档",
                        systemImage: showsArchivedFutureTasks ? "eye.slash" : "eye"
                    )
                }
            }

            if selectedTab == .sessions {
                Button {
                    taskStore.markCompletedTasksRead()
                } label: {
                    Label("全部已读", systemImage: "checkmark.circle")
                }
                .disabled(!taskStore.hasUnreadCompletedTasks)

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

    @ViewBuilder
    private var privacyBadge: some View {
        if taskStore.isPrivacyModeEnabled {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.caption)
                Text("privacy")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
    }

    private var columns: some View {
        HStack(spacing: 0) {
            TaskColumnView(
                status: .running,
                tasks: taskStore.tasks(for: .running),
                isPrivacyModeEnabled: taskStore.isPrivacyModeEnabled,
                selectedTaskID: $selectedTaskID
            )
            Divider()
            TaskColumnView(
                status: .completed,
                tasks: taskStore.tasks(for: .completed),
                isPrivacyModeEnabled: taskStore.isPrivacyModeEnabled,
                selectedTaskID: $selectedTaskID
            )
            Divider()
            TaskColumnView(
                status: .interrupted,
                tasks: taskStore.tasks(for: .interrupted),
                isPrivacyModeEnabled: taskStore.isPrivacyModeEnabled,
                selectedTaskID: $selectedTaskID
            )
            if showsArchivedTasks {
                Divider()
                TaskColumnView(
                    status: .history,
                    tasks: taskStore.tasks(for: .history),
                    isPrivacyModeEnabled: taskStore.isPrivacyModeEnabled,
                    selectedTaskID: $selectedTaskID
                )
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
            AgentRuntimeListView(
                runtimes: taskStore.runtimes,
                tokensByProvider: taskStore.runtimeTokenTotals()
            )
        case .tokenUsage:
            TokenUsageView(taskStore: taskStore)
        case .futureTasks:
            FutureTasksView(
                taskStore: taskStore,
                showsArchivedPlans: $showsArchivedFutureTasks
            )
        case .settings:
            SettingsView(taskStore: taskStore)
        }
    }
}
