import AppKit
import Foundation

struct TerminalAgentProcessProvider: AgentTaskProvider {
    let providerName = "Terminal Agents"

    func fetchTasks() async -> [AgentTask] {
        await Task.detached(priority: .utility) {
            readTasks()
        }.value
    }

    private func readTasks() -> [AgentTask] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "pid=,args="]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return []
        }

        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return output
            .split(separator: "\n")
            .compactMap(parseProcessLine)
    }

    private func parseProcessLine(_ line: Substring) -> AgentTask? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }

        let pid = String(trimmed[..<firstSpace])
        let args = trimmed[firstSpace...].trimmingCharacters(in: .whitespaces)
        let lowercased = args.lowercased()

        guard isTerminalAgentProcess(lowercased) else {
            return nil
        }

        let agent: String
        if lowercased.contains("claude") {
            agent = "Claude CLI"
        } else {
            agent = "Codex CLI"
        }

        return AgentTask(
            id: "process:\(pid)",
            title: "\(agent) 进程 \(pid)",
            summary: "终端 Agent 进程正在运行；为保护隐私不展示命令正文",
            agent: agent,
            model: "unknown",
            tokenUsage: 0,
            status: .running,
            updatedAt: Date()
        )
    }

    private func isTerminalAgentProcess(_ args: String) -> Bool {
        let hasAgentName = args.contains(" codex")
            || args.contains("/codex")
            || args.contains(" claude")
            || args.contains("/claude")

        guard hasAgentName else {
            return false
        }

        let excludedMarkers = [
            "codex.app/",
            "claude.app/",
            "chatgpt.app/",
            "app-server",
            "node_repl",
            "skycomputeruseclient",
            "extension-host",
            "agentspet",
            " rg ",
            "/bin/ps"
        ]

        return !excludedMarkers.contains { args.contains($0) }
    }
}

struct DesktopAppPresenceProvider: AgentTaskProvider {
    let providerName = "Desktop Apps"

    func fetchTasks() async -> [AgentTask] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app in
                task(for: app)
            }
        }
    }

    @MainActor
    private func task(for app: NSRunningApplication) -> AgentTask? {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return nil
        }

        let agent: String
        let title: String

        switch bundleIdentifier {
        case "com.openai.chat":
            agent = "ChatGPT Desktop"
            title = "ChatGPT 桌面端运行中"
        case "com.openai.codex":
            agent = "Codex Desktop"
            title = "Codex 桌面端运行中"
        case "com.anthropic.claudefordesktop", "com.anthropic.Claude":
            agent = "Claude Desktop"
            title = "Claude 桌面端运行中"
        default:
            return nil
        }

        return AgentTask(
            id: "desktop-app:\(bundleIdentifier)",
            title: title,
            summary: "仅检测到应用运行态，未读取对话正文或控制应用",
            agent: agent,
            model: "unknown",
            tokenUsage: 0,
            status: .completed,
            updatedAt: Date()
        )
    }
}
