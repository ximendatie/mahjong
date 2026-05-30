import AppKit
import ApplicationServices
import Foundation

struct ChatGPTLocalProvider: AgentTaskProvider {
    let providerID = AgentProviderID.chatGPT
    let providerName = "ChatGPT"

    private static let recentActivityWindow: TimeInterval = 24 * 60 * 60
    private static let bundleIdentifier = "com.openai.chat"

    private let applicationSupportDirectory: URL
    private let runningAppSnapshot: @Sendable () async -> ChatGPTRunningApp?
    private let isGeneratingResponse: @Sendable (pid_t) -> Bool
    private let isAccessibilityTrusted: @Sendable () -> Bool

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        runningAppSnapshot: @escaping @Sendable () async -> ChatGPTRunningApp? = {
            await MainActor.run {
                ChatGPTRunningApp.current(bundleIdentifier: ChatGPTLocalProvider.bundleIdentifier)
            }
        },
        isGeneratingResponse: @escaping @Sendable (pid_t) -> Bool = { pid in
            ChatGPTAccessibilityDetector.isGeneratingResponse(pid: pid)
        },
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = {
            ChatGPTAccessibilityDetector.isTrusted
        }
    ) {
        applicationSupportDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.openai.chat", isDirectory: true)
        self.runningAppSnapshot = runningAppSnapshot
        self.isGeneratingResponse = isGeneratingResponse
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }

    func fetchTasks() async -> [AgentTask] {
        let runningApp = await runningAppSnapshot()
        let latestActivityAt = await Task.detached(priority: .utility) {
            latestConversationActivity(in: applicationSupportDirectory)
        }.value

        guard runningApp != nil || latestActivityAt != nil else {
            return []
        }

        let accessibilityTrusted = isAccessibilityTrusted()
        let isGenerating = runningApp.map { accessibilityTrusted && isGeneratingResponse($0.pid) } ?? false
        let updatedAt = isGenerating ? Date() : (latestActivityAt ?? Date())
        let status = taskStatus(
            isGenerating: isGenerating,
            updatedAt: updatedAt
        )

        return [
            AgentTask(
                id: "chatgpt:desktop",
                title: "ChatGPT Desktop",
                summary: summary(
                    runningApp: runningApp,
                    latestActivityAt: latestActivityAt,
                    isGenerating: isGenerating,
                    accessibilityTrusted: accessibilityTrusted
                ),
                agent: "ChatGPT",
                providerID: providerID,
                model: "unknown",
                tokenUsage: 0,
                status: status,
                updatedAt: updatedAt
            )
        ]
    }

    private func taskStatus(isGenerating: Bool, updatedAt: Date) -> AgentTaskStatus {
        if isGenerating {
            return .running
        }

        return Date().timeIntervalSince(updatedAt) < Self.recentActivityWindow ? .completed : .history
    }

    private func summary(
        runningApp: ChatGPTRunningApp?,
        latestActivityAt: Date?,
        isGenerating: Bool,
        accessibilityTrusted: Bool
    ) -> String {
        if isGenerating {
            return "ChatGPT Desktop 正在生成响应"
        }

        if runningApp != nil && !accessibilityTrusted {
            return "ChatGPT Desktop 已运行；授权辅助功能后可识别生成中"
        }

        if runningApp != nil, latestActivityAt != nil {
            return "ChatGPT Desktop 已运行；最近有本地活动"
        }

        if runningApp != nil {
            return "ChatGPT Desktop 已运行"
        }

        return "ChatGPT Desktop 最近有本地活动"
    }
}

struct ChatGPTRunningApp: Sendable, Equatable {
    let pid: pid_t
    let bundleIdentifier: String
    let localizedName: String?

    @MainActor
    static func current(bundleIdentifier: String) -> ChatGPTRunningApp? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleIdentifier }
            .map {
                ChatGPTRunningApp(
                    pid: $0.processIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    localizedName: $0.localizedName
                )
            }
    }
}

private func latestConversationActivity(in directory: URL) -> Date? {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    var latest: Date?
    for case let fileURL as URL in enumerator {
        guard
            fileURL.pathExtension == "data",
            fileURL.path.contains("/conversations-v3-")
        else {
            continue
        }

        guard let resourceValues = try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey, .isRegularFileKey]
        ), resourceValues.isRegularFile == true,
           let modifiedAt = resourceValues.contentModificationDate else {
            continue
        }

        latest = max(latest ?? modifiedAt, modifiedAt)
    }

    return latest
}

enum ChatGPTAccessibilityDetector {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func isGeneratingResponse(pid: pid_t) -> Bool {
        guard isTrusted else {
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)
        var visited = 0
        return containsStopGeneratingControl(in: appElement, depth: 0, visited: &visited)
    }

    private static func containsStopGeneratingControl(
        in element: AXUIElement,
        depth: Int,
        visited: inout Int
    ) -> Bool {
        guard depth <= 8, visited < 500 else {
            return false
        }
        visited += 1

        if isStopGeneratingControl(element) {
            return true
        }

        guard let children = copyAttribute(.children, from: element) as? [AXUIElement] else {
            return false
        }

        for child in children {
            if containsStopGeneratingControl(in: child, depth: depth + 1, visited: &visited) {
                return true
            }
        }

        return false
    }

    private static func isStopGeneratingControl(_ element: AXUIElement) -> Bool {
        let role = copyAttribute(.role, from: element) as? String
        guard role == kAXButtonRole as String else {
            return false
        }

        let labels = [
            copyAttribute(.title, from: element),
            copyAttribute(.description, from: element),
            copyAttribute(.help, from: element)
        ]
            .compactMap { $0 as? String }
            .map { $0.lowercased() }

        return labels.contains { label in
            label.contains("stop generating")
                || label.contains("stop streaming")
                || label.contains("stop response")
                || label.contains("停止生成")
                || label.contains("停止响应")
        }
    }

    private static func copyAttribute(_ attribute: AccessibilityAttribute, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute.rawValue as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }
}

private enum AccessibilityAttribute: String {
    case children = "AXChildren"
    case description = "AXDescription"
    case help = "AXHelp"
    case role = "AXRole"
    case title = "AXTitle"
}
