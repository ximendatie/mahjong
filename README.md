# mahjong

[中文 README](README.zh-CN.md)

![mahjong visual showcase](docs/assets/showcase.png)

[Open the visual showcase](docs/showcase.html) ·
[Download a release](https://github.com/ximendatie/mahjong/releases) ·
[Launch playbook](docs/launch.md)

mahjong is a local-first macOS desktop companion for watching Codex, Claude,
ChatGPT, Hermes, Mira, and other AI agents work across desktop apps and terminal
sessions.

It is intentionally local-first and read-only: the app helps you see what your
agents are doing without sending data anywhere, mutating provider config, or
controlling other apps.

The name comes from the app's interaction model: when multiple agent sessions
are running, the floating companion switches between Mahjong tile icons so the
current workload is visible at a glance.

## Why People Try It

- See which local agents are running without digging through windows, tabs, and
  terminal sessions.
- Keep agent status visible in a small floating desktop companion.
- Inspect local task metadata while preserving a clear privacy boundary.
- Add new providers through small, reviewable parser and runtime integrations.

## What It Does

- Shows a floating Mahjong-tile desktop companion that reacts when local agents
  are working.
- Shows a Dock entry for mahjong with the red Mahjong tile app icon.
- Lets users hide the Dock entry after setup and keep mahjong as a menu bar pet.
- Opens a mahjong Board with running, completed, and archived task cards.
- Detects supported desktop apps and terminal agent processes.
- Shows the current app version and checks GitHub Releases for manual updates.
- Reads local session metadata for supported providers.
- Lets you draft future plans locally so you can capture work for later.

## Status

mahjong is early and usable for local testing. The current priority is a
trustworthy first-run experience: clear provider controls, diagnostics, privacy
defaults, and downloadable release builds.

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

| Provider | Task metadata | Runtime detection | Permission notes |
| --- | --- | --- | --- |
| Codex Desktop / Codex local sessions | Reads `~/.codex/session_index.jsonl` and `~/.codex/sessions/**/*.jsonl`. | Terminal process matching. | Local files only. |
| Claude local sessions | Reads `~/.claude/projects/**/*.jsonl`. | Terminal process matching. | Local files only. |
| Claude Desktop local sessions | Reads metadata from `~/Library/Application Support/Claude-3p/local-agent-mode-sessions/**/local_*.json` and `~/Library/Application Support/Claude-3p/claude-code-sessions/**/local_*.json`. | Correlates active sessions with local Claude Desktop `--resume` processes. | Local files only. |
| Hermes local sessions | Reads `~/.hermes/state.db` session/message metadata. | Detects Hermes Agent through `NSWorkspace` and Hermes CLI/gateway processes from `ps`. | Requires local SQLite metadata to exist. |
| Terminal agents | No conversation parsing. | Reads process metadata from `ps` for Codex, Claude, Hermes, and OpenClaw. | Process list only. |
| OpenClaw | Not parsed yet. | Detects OpenClaw Desktop and OpenClaw gateway/CLI process presence. | Presence detection only. |
| ChatGPT Desktop | Does not parse conversation text. Uses local conversation cache modification times as a recent-activity fallback. | Detects app presence through `NSWorkspace` and checks Accessibility button labels for generation state. | Accessibility is optional and only used for generation-state labels. |
| Trae CN | Reads ai-agent log timestamps plus session/task identifiers; does not parse conversation text. | Detects Trae CN Desktop app presence through `NSWorkspace` with process fallback. | Local log metadata only. |
| Mira | Not parsed yet. | Detects Mira Desktop app presence through `NSWorkspace` with process fallback. | Presence detection only. |

## Documentation

- [Visual showcase](docs/showcase.html)
- [Launch playbook](docs/launch.md)
- [Privacy and security notes](docs/privacy.md)
- [Architecture overview](docs/architecture.md)
- [Roadmap](docs/roadmap.md)
- [Provider development guide](docs/provider-development.md)
- [Provider scaffold](docs/provider-scaffold.md)
- [Auto-update strategy](docs/auto-update.md)
- [Contributor task board](docs/contributor-tasks.md)
- [Release guide](docs/release.md)
- [Contributing guide](CONTRIBUTING.md) / [中文](CONTRIBUTING.zh-CN.md)
- [Security policy](SECURITY.md) / [中文](SECURITY.zh-CN.md)

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

## Help It Reach More Users

- Star or share the repository with people who run multiple local agents.
- Try the release build and report first-run friction.
- Open an issue for a provider you want to see supported.
- Pick a small task from [Contributor Task Board](docs/contributor-tasks.md).

Suggested GitHub topics:

`macos`, `swift`, `ai-agents`, `codex`, `claude`, `chatgpt`, `local-first`,
`agent-monitoring`, `desktop-companion`

## Contributing

Issues, ideas, and pull requests are welcome. If you want to add a provider,
start with [docs/architecture.md](docs/architecture.md) and keep the provider
local-first, read-only, and conservative about what data appears in the UI.
