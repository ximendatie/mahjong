import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FutureTasksView: View {
    @ObservedObject var taskStore: AgentTaskStore
    @Binding var showsArchivedPlans: Bool
    @Binding var showsComposer: Bool
    @State private var title = ""
    @State private var note = ""
    @State private var editingTaskID: FutureTaskItem.ID?
    @State private var draggedTaskID: FutureTaskItem.ID?
    @State private var dropTargetTaskID: FutureTaskItem.ID?

    var body: some View {
        taskColumns
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sheet(isPresented: $showsComposer, onDismiss: clearEditor) {
                futureTaskComposerSheet
            }
    }

    private var taskColumns: some View {
        let tasks = taskStore.sortedFutureTasks()
        let openTasks = tasks.filter { !$0.isCompleted }
        let archivedTasks = tasks.filter(\.isCompleted)

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                futureTaskColumn(
                    title: "未来计划",
                    subtitle: "\(openTasks.count) 个待处理，\(archivedTasks.count) 个已归档",
                    tasks: openTasks,
                    emptyTitle: "暂无待处理计划",
                    count: openTasks.count
                )
                if showsArchivedPlans {
                    futureTaskColumn(
                        title: "已归档",
                        subtitle: "\(archivedTasks.count) 个已完成计划",
                        tasks: archivedTasks,
                        emptyTitle: "暂无归档计划",
                        count: archivedTasks.count
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func futureTaskColumn(
        title: String,
        subtitle: String,
        tasks: [FutureTaskItem],
        emptyTitle: String,
        count: Int
    ) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                FutureTaskColumnHeader(
                    title: title,
                    subtitle: subtitle,
                    count: count
                )

                if tasks.isEmpty {
                    EmptyFutureTasksView(title: emptyTitle)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(tasks) { task in
                            futureTaskCard(task)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.snappy(duration: 0.22, extraBounce: 0.04), value: tasks.map(\.id))
            .animation(.easeInOut(duration: 0.16), value: draggedTaskID)
            .animation(.easeInOut(duration: 0.16), value: dropTargetTaskID)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var canSaveTask: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveTask() {
        guard canSaveTask else {
            return
        }

        if let editingTaskID {
            taskStore.updateFutureTask(id: editingTaskID, title: title, note: note)
        } else {
            taskStore.createFutureTask(title: title, note: note)
        }
        closeComposer()
    }

    private func editTask(_ task: FutureTaskItem) {
        editingTaskID = task.id
        title = task.title
        note = task.note
        showsComposer = true
    }

    private func cancelEditing() {
        closeComposer()
    }

    private func clearEditor() {
        editingTaskID = nil
        title = ""
        note = ""
    }

    private func copyTask(_ task: FutureTaskItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let text = task.note.isEmpty ? task.title : "\(task.title)\n\n\(task.note)"
        pasteboard.setString(text, forType: .string)
    }

    private func futureTaskCard(_ task: FutureTaskItem) -> some View {
        FutureTaskCardView(
            task: task,
            isPrivacyModeEnabled: taskStore.isPrivacyModeEnabled,
            draggedTaskID: $draggedTaskID,
            dropTargetTaskID: $dropTargetTaskID,
            isDragging: draggedTaskID == task.id,
            onToggle: {
                taskStore.setFutureTaskCompleted(id: task.id, isCompleted: !task.isCompleted)
            },
            onCopy: {
                copyTask(task)
            },
            onEdit: {
                editTask(task)
            },
            onDelete: {
                taskStore.deleteFutureTask(id: task.id)
                if editingTaskID == task.id {
                    cancelEditing()
                }
                if draggedTaskID == task.id {
                    draggedTaskID = nil
                }
                if dropTargetTaskID == task.id {
                    dropTargetTaskID = nil
                }
            },
            onDragStarted: {
                withAnimation(.easeInOut(duration: 0.12)) {
                    draggedTaskID = task.id
                    dropTargetTaskID = task.id
                }
                return NSItemProvider(object: task.id.uuidString as NSString)
            },
            onMoveDraggedBefore: {
                guard let draggedTaskID,
                      dropTargetTaskID != task.id else {
                    return
                }
                withAnimation(.snappy(duration: 0.2, extraBounce: 0.03)) {
                    dropTargetTaskID = task.id
                    taskStore.moveFutureTask(id: draggedTaskID, before: task.id)
                }
            },
            onDropFinished: {
                withAnimation(.easeOut(duration: 0.16)) {
                    draggedTaskID = nil
                    dropTargetTaskID = nil
                }
            }
        )
    }

    private func closeComposer() {
        showsComposer = false
        clearEditor()
    }

    private var futureTaskComposerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(editingTaskID == nil ? "新建计划" : "编辑计划")
                    .font(.title3.weight(.semibold))
                Text(editingTaskID == nil ? "保存未来打算做的计划，不绑定 Agent 或模型。" : "修改已记录的计划内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("计划")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例如：整理第三阶段菜单栏方案", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveTask)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Button("取消", action: cancelEditing)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: saveTask) {
                    Label(editingTaskID == nil ? "记录计划" : "保存修改", systemImage: editingTaskID == nil ? "plus" : "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveTask)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 380, alignment: .topLeading)
    }
}

struct FutureTaskCardView: View {
    let task: FutureTaskItem
    let isPrivacyModeEnabled: Bool
    @Binding var draggedTaskID: FutureTaskItem.ID?
    @Binding var dropTargetTaskID: FutureTaskItem.ID?
    let isDragging: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDragStarted: () -> NSItemProvider
    let onMoveDraggedBefore: () -> Void
    let onDropFinished: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .help("拖动排序")

                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(task.isCompleted ? "标记为待处理" : "标记为完成")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isPrivacyModeEnabled ? "Private future plan" : task.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                            .strikethrough(task.isCompleted)
                            .lineLimit(2)

                        metadataPill(task.isCompleted ? "已归档" : "待处理")
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        actionButton(systemImage: "doc.on.doc", help: "复制计划", action: onCopy)
                        actionButton(systemImage: "pencil", help: "编辑计划", action: onEdit)
                        actionButton(systemImage: "trash", help: "删除计划", role: .destructive, action: onDelete)
                    }
                }

                if !task.note.isEmpty {
                    Text(isPrivacyModeEnabled ? "Note hidden by privacy mode" : task.note)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isDragging ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .scaleEffect(isDragging ? 0.99 : 1)
        .shadow(color: isDragging ? Color.black.opacity(0.12) : .clear, radius: 8, y: 4)
        .onDrag(onDragStarted)
        .onDrop(of: [UTType.text.identifier], delegate: FutureTaskDropDelegate(task: task, draggedTaskID: $draggedTaskID, dropTargetTaskID: $dropTargetTaskID, onMoveDraggedBefore: onMoveDraggedBefore, onDropFinished: onDropFinished))
        .animation(.snappy(duration: 0.18, extraBounce: 0.02), value: isDragging)
        .animation(.easeInOut(duration: 0.14), value: dropTargetTaskID == task.id)
    }

    private var borderColor: Color {
        if isDragging {
            return Color.accentColor.opacity(0.4)
        }
        if dropTargetTaskID == task.id {
            return Color.accentColor.opacity(0.22)
        }
        return Color.white.opacity(0.06)
    }

    private var borderWidth: CGFloat {
        if isDragging {
            return 1.5
        }
        if dropTargetTaskID == task.id {
            return 1.25
        }
        return 1
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(task.isCompleted ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill((task.isCompleted ? Color.secondary : Color.accentColor).opacity(0.12)))
    }

    private func actionButton(
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct FutureTaskDropDelegate: DropDelegate {
    let task: FutureTaskItem
    @Binding var draggedTaskID: FutureTaskItem.ID?
    @Binding var dropTargetTaskID: FutureTaskItem.ID?
    let onMoveDraggedBefore: () -> Void
    let onDropFinished: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID, draggedTaskID != task.id else {
            return
        }

        onMoveDraggedBefore()
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropFinished()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropExited(info: DropInfo) {
        guard dropTargetTaskID == task.id else {
            return
        }
        dropTargetTaskID = nil
    }
}

struct FutureTaskColumnHeader: View {
    let title: String
    let subtitle: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.05)))
        }
        .padding(.bottom, 6)
    }
}

struct EmptyFutureTasksView: View {
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
            Text("这里会显示你之后要推进的事项。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}
