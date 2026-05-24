# AgentsPet

macOS desktop pet MVP for monitoring parallel Agent tasks.

## Run

```bash
script/build_and_run.sh
```

The first version uses local mock task data. Click the pet to open the Agent
Board, then use the board controls to add, complete, and archive sample tasks.

The script builds a local `.app` bundle at `.build/AgentsPet.app` and opens it
through macOS LaunchServices.

## Safety Boundaries

AgentsPet uses read-only local observation by default:

- It does not show full conversation bodies by default. Task cards only show
  thread title, status, model, provider, and token usage when those fields are
  available.
- It does not write to Codex, Claude, ChatGPT, or terminal-agent config files.
- It does not control Codex Desktop, Claude Desktop, ChatGPT Desktop, terminal
  agents, or any provider app.
- It does not send messages, execute commands, or trigger provider-side actions.

## Current Providers

- Codex Desktop / Codex local sessions: reads `~/.codex/session_index.jsonl`
  and `~/.codex/sessions/**/*.jsonl`.
- Claude local sessions: reads `~/.claude/projects/**/*.jsonl`.
- Terminal agents: reads local process metadata from `ps` and records each
  matching process as its own task.
- OpenClaw: detects OpenClaw Desktop and OpenClaw gateway/CLI process presence
  only.
- ChatGPT / Codex / Claude / OpenClaw desktop apps: detects app presence through
  `NSWorkspace`; no conversation data is parsed for ChatGPT Desktop in this
  MVP.
