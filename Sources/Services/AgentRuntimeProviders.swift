import AppKit
import Foundation

struct TerminalAgentRuntimeProvider: AgentRuntimeProvider {
    let providerName = "Terminal Agents"

    func fetchRuntimes() async -> [AgentRuntime] {
        await Task.detached(priority: .utility) {
            readRuntimes()
        }.value
    }

    private func readRuntimes() -> [AgentRuntime] {
        let output = ProcessListReader.readProcessList()
        var codexCount = 0
        var claudeCount = 0
        var hermesCount = 0
        var openClawCount = 0

        for line in output.split(separator: "\n") {
            guard let args = ProcessListReader.arguments(from: line) else {
                continue
            }

            let lowercased = args.lowercased()
            if ProcessListReader.isOpenClawProcess(lowercased) {
                openClawCount += 1
                continue
            }

            if ProcessListReader.isHermesProcess(lowercased) {
                hermesCount += 1
                continue
            }

            guard ProcessListReader.isTerminalAgentProcess(lowercased) else {
                continue
            }

            if lowercased.contains("claude") {
                claudeCount += 1
            } else {
                codexCount += 1
            }
        }

        var runtimes: [AgentRuntime] = []
        if codexCount > 0 {
            runtimes.append(
                AgentRuntime(
                    id: "terminal:codex",
                    name: "Codex CLI",
                    provider: "Codex",
                    kind: .terminal,
                    summary: "检测到 Codex 终端运行态；任务卡仍以 Codex session 为准",
                    processCount: codexCount,
                    iconBundleIdentifier: AgentRuntimeIconBundle.codex
                )
            )
        }

        if claudeCount > 0 {
            runtimes.append(
                AgentRuntime(
                    id: "terminal:claude",
                    name: "Claude CLI",
                    provider: "Claude",
                    kind: .terminal,
                    summary: "检测到 Claude 终端运行态；任务卡仍以 Claude session 为准",
                    processCount: claudeCount,
                    iconBundleIdentifier: AgentRuntimeIconBundle.claude
                )
            )
        }

        if hermesCount > 0 {
            runtimes.append(
                AgentRuntime(
                    id: "terminal:hermes",
                    name: "Hermes CLI",
                    provider: "Hermes",
                    kind: .terminal,
                    summary: "检测到 Hermes 终端运行态；任务卡从本地 Hermes state.db 读取",
                    processCount: hermesCount,
                    iconResourceName: "AgentIcons/hermes"
                )
            )
        }

        if openClawCount > 0 {
            runtimes.append(
                AgentRuntime(
                    id: "terminal:openclaw",
                    name: "OpenClaw Gateway",
                    provider: "OpenClaw",
                    kind: .terminal,
                    summary: "检测到 OpenClaw gateway/CLI 运行态；仅观测是否运行",
                    processCount: openClawCount,
                    iconBundleIdentifier: AgentRuntimeIconBundle.openClaw
                )
            )
        }

        return runtimes
    }
}

struct DesktopAppRuntimeProvider: AgentRuntimeProvider {
    let providerName = "Desktop Apps"

    func fetchRuntimes() async -> [AgentRuntime] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app in
                runtime(for: app)
            }
        }
    }

    @MainActor
    private func runtime(for app: NSRunningApplication) -> AgentRuntime? {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return nil
        }

        switch bundleIdentifier {
        case "com.openai.chat":
            return AgentRuntime(
                id: "desktop:chatgpt",
                name: "ChatGPT Desktop",
                provider: "OpenAI",
                kind: .desktopApp,
                summary: "已运行；当前不安全解析对话任务粒度",
                bundleIdentifier: bundleIdentifier,
                iconBundleIdentifier: AgentRuntimeIconBundle.chatGPT
            )
        case "com.openai.codex":
            return AgentRuntime(
                id: "desktop:codex",
                name: "Codex Desktop",
                provider: "Codex",
                kind: .desktopApp,
                summary: "已运行；任务卡从本地 Codex session 读取",
                bundleIdentifier: bundleIdentifier,
                iconBundleIdentifier: AgentRuntimeIconBundle.codex
            )
        case "com.anthropic.claudefordesktop", "com.anthropic.Claude":
            return AgentRuntime(
                id: "desktop:claude",
                name: "Claude Desktop",
                provider: "Claude",
                kind: .desktopApp,
                summary: "已运行；任务卡从可用本地 session 记录读取",
                bundleIdentifier: bundleIdentifier,
                iconBundleIdentifier: AgentRuntimeIconBundle.claude
            )
        case "ai.openclaw.mac":
            return AgentRuntime(
                id: "desktop:openclaw",
                name: "OpenClaw Desktop",
                provider: "OpenClaw",
                kind: .desktopApp,
                summary: "已运行；仅观测桌面端运行状态",
                bundleIdentifier: bundleIdentifier,
                iconBundleIdentifier: AgentRuntimeIconBundle.openClaw
            )
        case "com.nousresearch.hermes":
            return AgentRuntime(
                id: "desktop:hermes",
                name: "Hermes Agent",
                provider: "Hermes",
                kind: .desktopApp,
                summary: "已运行；任务卡从本地 Hermes state.db 读取",
                bundleIdentifier: bundleIdentifier,
                iconBundleIdentifier: AgentRuntimeIconBundle.hermes
            )
        default:
            return nil
        }
    }
}

enum AgentRuntimeIconBundle {
    static let chatGPT = "com.openai.chat"
    static let codex = "com.openai.codex"
    static let claude = "com.anthropic.claudefordesktop"
    static let hermes = "com.nousresearch.hermes"
    static let openClaw = "ai.openclaw.mac"
}

enum ProcessListReader {
    static func readProcessList() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "pid=,args="]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    static func arguments(from line: Substring) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }

        return trimmed[firstSpace...].trimmingCharacters(in: .whitespaces)
    }

    static func isTerminalAgentProcess(_ args: String) -> Bool {
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

    static func isOpenClawProcess(_ args: String) -> Bool {
        let hasOpenClawName = args.contains(" openclaw")
            || args.contains("/openclaw")

        guard hasOpenClawName else {
            return false
        }

        let excludedMarkers = [
            "openclaw.app/",
            "agentspet",
            " rg ",
            "/bin/ps"
        ]

        return !excludedMarkers.contains { args.contains($0) }
    }

    static func isHermesProcess(_ args: String) -> Bool {
        let hasHermesName = args.contains(" hermes")
            || args.contains("/hermes")
            || args.contains("/.hermes/hermes-agent/")

        guard hasHermesName else {
            return false
        }

        let excludedMarkers = [
            "hermes agent.app/",
            "agentspet",
            " rg ",
            "/bin/ps"
        ]

        return !excludedMarkers.contains { args.contains($0) }
    }
}
