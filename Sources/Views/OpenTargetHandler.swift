import AppKit

enum OpenTargetHandler {
    static func open(_ task: AgentTask) {
        if let openURL = task.openURL {
            NSWorkspace.shared.open(openURL)
            return
        }

        activateApp(named: task.agent)
    }

    static func open(_ runtime: AgentRuntime) {
        if let bundleIdentifier = runtime.bundleIdentifier {
            activateApp(bundleIdentifier: bundleIdentifier)
            return
        }

        activateApp(named: runtime.provider)
    }

    private static func activateApp(bundleIdentifier: String) {
        let runningApp = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier
        }
        runningApp?.activate()
    }

    private static func activateApp(named name: String) {
        let lowercasedName = name.lowercased()
        let runningApp = NSWorkspace.shared.runningApplications.first { app in
            app.localizedName?.lowercased().contains(lowercasedName) == true
        }
        runningApp?.activate()
    }
}
