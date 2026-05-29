# Architecture Overview

AgentsPet has three main layers:

- Providers read local metadata and convert it into app-level models.
- `AgentTaskStore` merges provider data, local overrides, runtime state, and
  future task drafts.
- SwiftUI/AppKit views render the floating pet and Agent Board.

## Models

- `AgentTask` is the normalized card shown in the board.
- `AgentRuntime` represents a detected desktop app or terminal runtime.
- `FutureAgentTask` stores local task drafts created by the user.

## Providers

Task providers conform to `AgentTaskProvider`:

```swift
protocol AgentTaskProvider: Sendable {
    var providerName: String { get }
    func fetchTasks() async -> [AgentTask]
}
```

Runtime providers conform to `AgentRuntimeProvider`:

```swift
protocol AgentRuntimeProvider: Sendable {
    var providerName: String { get }
    func fetchRuntimes() async -> [AgentRuntime]
}
```

Provider implementations should be defensive. Missing files, schema drift, and
permission failures should return empty results or partial metadata instead of
crashing the app.

## Store

`AgentTaskStore` owns the app state used by the UI. It:

- Fetches task and runtime providers concurrently.
- Deduplicates tasks and runtimes by stable IDs.
- Applies local complete/archive overrides.
- Moves completed tasks older than today into history.
- Persists future task drafts in `UserDefaults`.

## UI

- `PetView` renders the floating companion.
- `BoardView` renders task columns, runtime status, and future task drafts.
- `PetWindowController` and `BoardWindowController` bridge SwiftUI views into
  macOS windows.

## Adding A Provider

1. Decide whether the provider exposes tasks, runtimes, or both.
2. Add a focused provider type under `Sources/Services`.
3. Normalize local metadata into `AgentTask` or `AgentRuntime`.
4. Add the provider to the default list in `AgentTaskStore`.
5. Add fixture-based tests for parsing and status inference.
6. Update `README.md` and `docs/privacy.md` with the data paths and behavior.
