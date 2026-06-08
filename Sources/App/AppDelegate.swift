import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let taskStore = AgentTaskStore()
    private var petWindowController: PetWindowController?
    private var boardWindowController: BoardWindowController?
    private var menuBarController: MenuBarController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        let boardWindowController = BoardWindowController(taskStore: taskStore)
        let petWindowController = PetWindowController(taskStore: taskStore) {
            boardWindowController.toggle()
        }
        let menuBarController = MenuBarController(taskStore: taskStore) {
            boardWindowController.show()
        }

        self.boardWindowController = boardWindowController
        self.petWindowController = petWindowController
        self.menuBarController = menuBarController

        taskStore.$isDockIconEnabled
            .sink { [weak self] isEnabled in
                self?.applyDockIconMode(isEnabled)
            }
            .store(in: &cancellables)

        applyDockIconMode(taskStore.isDockIconEnabled)
        taskStore.startRefreshing()
        petWindowController.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func openBoard() {
        boardWindowController?.show()
    }

    @objc private func refresh() {
        taskStore.refreshNow()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(editMenuItem)

        let appMenu = NSMenu(title: "mahjong")
        appMenu.addItem(NSMenuItem(title: "打开 Board", action: #selector(openBoard), keyEquivalent: "b", target: self))
        appMenu.addItem(NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 mahjong", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", target: NSApp))
        appMenuItem.submenu = appMenu

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z", target: nil))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z", target: nil))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x", target: nil))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c", target: nil))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v", target: nil))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a", target: nil))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func applyDockIconMode(_ isEnabled: Bool) {
        if isEnabled {
            NSApp.setActivationPolicy(.regular)
            setupMainMenu()
        } else {
            NSApp.setActivationPolicy(.accessory)
            NSApp.mainMenu = nil
        }
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject?) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}
