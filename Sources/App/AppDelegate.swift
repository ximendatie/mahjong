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
        let windowMenuItem = NSMenuItem()

        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(windowMenuItem)

        let appMenu = NSMenu(title: "mahjong")
        appMenu.addItem(NSMenuItem(title: "打开 Board", action: #selector(openBoard), keyEquivalent: "b", target: self))
        appMenu.addItem(NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 mahjong", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h", target: NSApp))
        appMenu.addItem(NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h", target: NSApp, modifiers: [.command, .option]))
        appMenu.addItem(NSMenuItem(title: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "", target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 mahjong", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", target: NSApp))
        appMenuItem.submenu = appMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m", target: nil))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "", target: nil))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "打开 Board", action: #selector(openBoard), keyEquivalent: "0", target: self))
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }
}

private extension NSMenuItem {
    convenience init(
        title: String,
        action: Selector?,
        keyEquivalent: String,
        target: AnyObject?,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
        keyEquivalentModifierMask = modifiers
    }
}
