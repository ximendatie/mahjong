import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let taskStore = AgentTaskStore()
    private var petWindowController: PetWindowController?
    private var boardWindowController: BoardWindowController?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
}
