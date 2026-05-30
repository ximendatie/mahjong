import SwiftUI

struct TaskColumnView: View {
    let status: AgentTaskStatus
    let tasks: [AgentTask]
    let isPrivacyModeEnabled: Bool
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
                        TaskCardView(
                            task: task,
                            isSelected: selectedTaskID == task.id,
                            isPrivacyModeEnabled: isPrivacyModeEnabled
                        )
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

struct EmptyColumnView: View {
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
        case .interrupted: "exclamationmark.circle"
        case .history: "clock"
        }
    }
}
