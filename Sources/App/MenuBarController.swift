import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let taskStore: AgentTaskStore
    private let onOpenBoard: () -> Void
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingStatusItemUpdate: Task<Void, Never>?

    init(taskStore: AgentTaskStore, onOpenBoard: @escaping () -> Void) {
        self.taskStore = taskStore
        self.onOpenBoard = onOpenBoard
        super.init()

        taskStore.$isMenuBarEnabled
            .sink { [weak self] isEnabled in
                self?.setStatusItemEnabled(isEnabled)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(taskStore.$tasks, taskStore.$runtimes, taskStore.$isPrivacyModeEnabled)
            .sink { [weak self] _, _, _ in
                self?.scheduleStatusItemUpdate()
            }
            .store(in: &cancellables)

        setStatusItemEnabled(taskStore.isMenuBarEnabled)
    }

    deinit {
        pendingStatusItemUpdate?.cancel()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func setStatusItemEnabled(_ isEnabled: Bool) {
        if isEnabled {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let menu = NSMenu()
                menu.delegate = self
                item.menu = menu
                item.isVisible = true
                statusItem = item
            }
            updateStatusItem()
            rebuildMenu()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func updateStatusItem() {
        guard let statusItem, let button = statusItem.button else {
            return
        }

        button.image = nil
        button.title = taskStore.runningCount > 0 ? "🀄️ \(taskStore.runningCount)" : "🀄️"
        statusItem.length = NSStatusItem.variableLength
        button.toolTip = "\(taskStore.runningCount) running, \(taskStore.runningAgentCount) agents"
    }

    private func scheduleStatusItemUpdate() {
        pendingStatusItemUpdate?.cancel()
        pendingStatusItemUpdate = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else {
                return
            }
            self.updateStatusItem()
        }
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else {
            return
        }

        menu.removeAllItems()

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !recentResolvedTasks.isEmpty {
            for task in recentResolvedTasks.prefix(3) {
                let item = NSMenuItem(title: menuTitle(for: task), action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开 Board", action: #selector(openBoard), keyEquivalent: "b", target: self))
        menu.addItem(NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r", target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 mahjong", action: #selector(quit), keyEquivalent: "q", target: self))
    }

    private var statusTitle: String {
        "\(taskStore.runningCount) running / \(taskStore.runningAgentCount) agents"
    }

    private var recentResolvedTasks: [AgentTask] {
        taskStore.tasks
            .filter { $0.status == .completed || $0.status == .interrupted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func menuTitle(for task: AgentTask) -> String {
        let title = taskStore.isPrivacyModeEnabled ? "\(task.status.title)任务" : task.title
        return "\(task.status.title): \(title)".truncatedMenuTitle
    }

    @objc private func openBoard() {
        onOpenBoard()
    }

    @objc private func refresh() {
        taskStore.refreshNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}

private extension String {
    var truncatedMenuTitle: String {
        guard count > 30 else {
            return self
        }
        return "\(prefix(27))..."
    }
}
