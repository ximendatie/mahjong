import SwiftUI

struct FutureTasksView: View {
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
                Text("仅保存到 mahjong 本地计划列表")
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
                    FutureTaskCardView(task: task, isPrivacyModeEnabled: taskStore.isPrivacyModeEnabled) {
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

struct FutureTaskCardView: View {
    let task: FutureAgentTask
    let isPrivacyModeEnabled: Bool
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
                    Text(isPrivacyModeEnabled ? "Private future task" : task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除未来任务")
                }

                Text(isPrivacyModeEnabled ? "Prompt hidden by privacy mode" : task.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                VStack(spacing: 5) {
                    metadataRow("Agent", task.agent.title)
                    metadataRow("Model", isPrivacyModeEnabled ? "Hidden" : (task.modelHint.isEmpty ? task.agent.modelPlaceholder : task.modelHint))
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

struct EmptyFutureTasksView: View {
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

