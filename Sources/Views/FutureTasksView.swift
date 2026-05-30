import AppKit
import SwiftUI

struct FutureTasksView: View {
    @ObservedObject var taskStore: AgentTaskStore
    @State private var title = ""
    @State private var note = ""

    var body: some View {
        HStack(spacing: 0) {
            quickCapture
                .frame(width: 340)
            Divider()
            taskList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var quickCapture: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("快速记录")
                    .font(.headline)
                Text("保存未来打算做的计划，不绑定 Agent 或模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("计划")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例如：整理第三阶段菜单栏方案", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createTask)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }

            Button(action: createTask) {
                Label("记录计划", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreateTask)

            Spacer()
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.025))
    }

    private var taskList: some View {
        let tasks = taskStore.sortedFutureTasks()
        let openCount = tasks.filter { !$0.isCompleted }.count

        return ScrollView {
            LazyVStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("未来计划")
                            .font(.headline)
                        Text("\(openCount) 个待处理，\(tasks.count - openCount) 个已完成")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    FutureTaskCardView(
                        task: task,
                        isPrivacyModeEnabled: taskStore.isPrivacyModeEnabled,
                        onToggle: {
                            taskStore.setFutureTaskCompleted(id: task.id, isCompleted: !task.isCompleted)
                        },
                        onCopy: {
                            copyTask(task)
                        },
                        onDelete: {
                            taskStore.deleteFutureTask(id: task.id)
                        }
                    )
                }

                if tasks.isEmpty {
                    EmptyFutureTasksView()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var canCreateTask: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createTask() {
        guard canCreateTask else {
            return
        }

        taskStore.createFutureTask(title: title, note: note)
        title = ""
        note = ""
    }

    private func copyTask(_ task: FutureTaskItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let text = task.note.isEmpty ? task.title : "\(task.title)\n\n\(task.note)"
        pasteboard.setString(text, forType: .string)
    }
}

struct FutureTaskCardView: View {
    let task: FutureTaskItem
    let isPrivacyModeEnabled: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "标记为待处理" : "标记为完成")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isPrivacyModeEnabled ? "Private future plan" : task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                        .lineLimit(2)
                    Spacer()
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制计划")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除计划")
                }

                if !task.note.isEmpty {
                    Text(isPrivacyModeEnabled ? "Note hidden by privacy mode" : task.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }

                HStack(spacing: 10) {
                    metadataPill(task.isCompleted ? "已完成" : "待处理")
                    Text(Self.dateFormatter.string(from: task.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(task.isCompleted ? 0.55 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(task.isCompleted ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill((task.isCompleted ? Color.secondary : Color.accentColor).opacity(0.12)))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct EmptyFutureTasksView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("暂无未来计划")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}
