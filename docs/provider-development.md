# Provider Development Guide

mahjong providers turn local AI-agent activity into compact task cards and runtime rows. A provider must stay local-first, read-only, and conservative about what it displays.

## Provider Types

| Type | Protocol | Use when |
| --- | --- | --- |
| Task provider | `AgentTaskProvider` | Local metadata can safely produce task cards with title, status, model, token usage, or timestamps. |
| Runtime provider | `AgentRuntimeProvider` | You can only tell whether an app or process is running. |
| Both | Both protocols | The tool exposes safe task metadata and also has a useful runtime signal. |

Do not parse full conversation bodies just to create a task. Prefer explicit metadata, event names, timestamps, status fields, and local process state.

## Required Boundaries

Every provider must follow these rules:

- Read local files, local databases, process lists, or app runtime state only.
- Never upload local session data.
- Never write provider config, cache, database, or session files.
- Never send messages or trigger provider-side actions.
- Avoid displaying full prompts, responses, or conversation bodies by default.
- Treat missing files, permission failures, and schema drift as partial data or empty results, not app crashes.
- Document every local path and permission-sensitive behavior.

## Implementation Checklist

1. Add or update `AgentProviderID` in `Sources/Models/ProviderSettings.swift`.
2. Add an `AgentProviderDescriptor` with display name, default state, data paths, privacy description, and short UI detail.
3. Add a focused provider under `Sources/Services`.
4. Register the provider in `AgentTaskStore` only after it has tests.
5. Add fixture tests under `Tests/MahjongTests`.
6. Update `README.md`, `README.zh-CN.md`, and `docs/privacy.md`.
7. If the provider has new user-visible states, update diagnostics copy.

## Minimal Task Provider

```swift
import Foundation

struct ExampleLocalProvider: AgentTaskProvider {
    let providerID = AgentProviderID.example
    let providerName = "Example"

    func fetchTasks() async -> [AgentTask] {
        let sessionURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".example/sessions/latest.json")

        guard FileManager.default.fileExists(atPath: sessionURL.path) else {
            return []
        }

        return [
            AgentTask(
                id: "example:latest",
                title: "Example local task",
                summary: "Example has recent local activity",
                agent: "Example",
                providerID: providerID,
                model: "unknown",
                tokenUsage: 0,
                status: .completed
            )
        ]
    }
}
```

## Minimal Runtime Provider

```swift
import Foundation

struct ExampleRuntimeProvider: AgentRuntimeProvider {
    let providerID = AgentProviderID.exampleRuntime
    let providerName = "Example Runtime"

    func fetchRuntimes() async -> [AgentRuntime] {
        let processList = ProcessListReader.readProcessList().lowercased()
        guard processList.contains(" example-cli ") else {
            return []
        }

        return [
            AgentRuntime(
                id: "runtime:example-cli",
                name: "Example CLI",
                provider: "Example",
                providerID: providerID,
                kind: .terminal,
                summary: "Detected Example CLI process"
            )
        ]
    }
}
```

## Fixture Tests

Provider tests should use temporary directories and small fixture files. Do not depend on the contributor's real home directory.

Test at least:

- Missing path returns `[]`.
- A valid fixture maps provider ID, title, status, and timestamps correctly.
- Unknown or partial schema does not crash.
- Running, completed, and interrupted states are covered when the provider can infer them.
- Privacy-sensitive fields are summarized, not exposed verbatim.

## Diagnostics Guidance

Diagnostics should help users understand why a provider is silent:

- Missing data path: say which configured local path was not found.
- Permission missing: explain the exact macOS setting or app permission needed.
- No data: say the provider is enabled but no active or recent records were found.
- Partial data: show the best safe metadata and avoid alarming language.

For permission-sensitive features, include a direct UI action when possible, such as opening System Settings for Accessibility.

## Documentation Updates

When adding or changing a provider, update:

- `README.md`: provider table and user-visible behavior.
- `README.zh-CN.md`: Chinese provider table.
- `docs/privacy.md`: local data paths, permissions, and what is displayed.
- `docs/architecture.md`: only when the provider changes architecture or shared contracts.

## Review Checklist

A provider PR is ready for review when:

- It is local-first and read-only.
- It has a descriptor and stable provider ID.
- It has focused fixture tests.
- It handles missing paths and schema drift without crashing.
- It documents local paths and privacy behavior.
- It avoids full conversation-body display by default.
