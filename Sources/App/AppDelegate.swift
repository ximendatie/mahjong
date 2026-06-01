import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let taskStore = AgentTaskStore()
    private var petWindowController: PetWindowController?
    private var boardWindowController: BoardWindowController?
    private var menuBarController: MenuBarController?

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
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "mahjong")
        appMenu.addItem(NSMenuItem(title: "打开 Board", action: #selector(openBoard), keyEquivalent: "b", target: self))
        appMenu.addItem(NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 mahjong", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", target: NSApp))
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject?) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}
