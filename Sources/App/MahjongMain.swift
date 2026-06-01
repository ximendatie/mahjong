import AppKit

@main
enum MahjongMain {
    @MainActor private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = appDelegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
