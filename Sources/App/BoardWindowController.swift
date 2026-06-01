import AppKit
import SwiftUI

@MainActor
final class BoardWindowController: NSObject, NSWindowDelegate {
    private let window: AgentBoardPanel
    private var isShowing = false

    init(taskStore: AgentTaskStore) {
        let rootView = BoardView(taskStore: taskStore)
        let frame = Self.defaultFrame()

        window = AgentBoardPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "mahjong Board"
        window.minSize = NSSize(width: 760, height: 420)
        window.level = .normal
        window.hidesOnDeactivate = false
        window.isFloatingPanel = false
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: rootView)

        super.init()
        window.delegate = self
    }

    func toggle() {
        if window.isVisible || isShowing {
            isShowing = false
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        isShowing = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShowing else {
                return
            }

            NSApp.activate()
            self.window.centerIfNeeded()
            self.window.makeKeyAndOrderFront(nil)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        isShowing = window.isVisible
    }

    func windowWillClose(_ notification: Notification) {
        isShowing = false
    }

    private static func defaultFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 920, height: 560)
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private final class AgentBoardPanel: NSPanel {
    private var hasSetInitialPosition = false

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    func centerIfNeeded() {
        guard !hasSetInitialPosition else {
            return
        }

        center()
        hasSetInitialPosition = true
    }
}
