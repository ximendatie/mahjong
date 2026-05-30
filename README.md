# mahjong

mahjong is a tiny macOS desktop companion for watching local AI agent work
across desktop apps and terminal sessions.

It is intentionally local-first and read-only: the app helps you see what your
agents are doing without sending data anywhere, mutating provider config, or
controlling other apps.

The name comes from the app's interaction model: when multiple agent sessions
are running, the floating companion switches between Mahjong tile icons so the
current workload is visible at a glance.

## What It Does

- Shows a floating Mahjong-tile desktop companion that reacts when local agents
  are working.
- Opens a mahjong Board with running, completed, and archived task cards.
- Detects supported desktop apps and terminal agent processes.
- Reads local session metadata for supported providers.
- Lets you draft "future tasks" locally so you can capture work for later.

## Run

```bash
script/build_and_run.sh
```

The first version uses local mock task data. Click the pet to open the Agent
Board, then use the board controls to add, complete, and archive sample tasks.

The script builds a local `.app` bundle at `.build/mahjong.app` and opens it
through macOS LaunchServices.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- ImageMagick `magick` command, optional, for regenerating the app icon during
  local bundle builds

## Build

```bash
swift build
```

## Release Zip

```bash
script/build_release_zip.sh
```

The release script builds `.build/mahjong.app` and packages it as
`.build/dist/mahjong.zip`.

## Test

```bash
swift test
```

## Safety Boundaries

mahjong uses read-only local observation by default:

- It does not show full conversation bodies by default. Task cards only show
  thread title, status, model, provider, and token usage when those fields are
  available.
- It does not write to Codex, Claude, ChatGPT, or terminal-agent config files.
- It does not control Codex Desktop, Claude Desktop, ChatGPT Desktop, terminal
  agents, or any provider app.
- It does not send messages, execute commands, or trigger provider-side actions.
- It does not upload local session data or contact a remote service.

## Current Providers

| Provider | Current behavior |
| --- | --- |
| Codex Desktop / Codex local sessions | Reads `~/.codex/session_index.jsonl` and `~/.codex/sessions/**/*.jsonl`. |
| Claude local sessions | Reads `~/.claude/projects/**/*.jsonl`. |
| Claude Desktop local sessions | Reads metadata from `~/Library/Application Support/Claude-3p/local-agent-mode-sessions/**/local_*.json` and `~/Library/Application Support/Claude-3p/claude-code-sessions/**/local_*.json`, then correlates active sessions with local Claude Desktop `--resume` processes. |
| Hermes local sessions | Reads `~/.hermes/state.db` session/message metadata and detects Hermes Agent desktop app presence through `NSWorkspace` plus Hermes CLI/gateway process presence from `ps`. |
| Terminal agents | Reads local process metadata from `ps` and records matching Codex, Claude, Hermes, and OpenClaw processes. |
| OpenClaw | Detects OpenClaw Desktop and OpenClaw gateway/CLI process presence only. |
| ChatGPT Desktop | Detects app presence through `NSWorkspace`; no conversation data is parsed in this MVP. |

## Documentation

- [Privacy and security notes](docs/privacy.md)
- [Architecture overview](docs/architecture.md)
- [Roadmap](docs/roadmap.md)
- [Contributing guide](CONTRIBUTING.md)

## Roadmap

Good contribution areas:

- Provider toggles and a lightweight settings surface.
- More local agent providers.
- Better status inference for long-running or paused sessions.
- Signed and notarized release builds.
- Menu bar mode and notification preferences.
- More UI polish and accessibility improvements.
- Localized UI strings.
- Broader test coverage for provider parsers.

## Contributing

Issues, ideas, and pull requests are welcome. If you want to add a provider,
start with [docs/architecture.md](docs/architecture.md) and keep the provider
local-first, read-only, and conservative about what data appears in the UI.
