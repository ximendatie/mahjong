# Privacy Notes

AgentsPet is designed as a local-first observer for AI agent activity on macOS.
It does not upload session data and does not control provider apps.

## Local Data Read By Current Providers

| Provider | Local data used |
| --- | --- |
| Codex | `~/.codex/session_index.jsonl`, `~/.codex/sessions/**/*.jsonl` |
| Claude CLI | `~/.claude/projects/**/*.jsonl` |
| Claude Desktop | `~/Library/Application Support/Claude-3p/local-agent-mode-sessions/**/local_*.json`, `~/Library/Application Support/Claude-3p/claude-code-sessions/**/local_*.json` |
| Hermes | `~/.hermes/state.db` |
| Desktop apps | Running application bundle identifiers from `NSWorkspace` |
| Terminal agents | Process metadata from `/bin/ps` |

## What Is Displayed

Task cards are intended to show compact metadata such as title, provider,
status, model, token usage, and recent activity time. The app avoids displaying
full conversation bodies by default.

## What AgentsPet Does Not Do

- It does not send prompts, session files, or task data to a server.
- It does not write to provider config, session, or cache files.
- It does not send messages to providers.
- It does not execute commands on behalf of providers.
- It does not control Codex Desktop, Claude Desktop, ChatGPT Desktop, OpenClaw,
  Hermes, or terminal agent processes.

## Contributor Expectations

New providers should follow the same boundaries. If a contribution needs a new
kind of data access, document it in `README.md` and this file, and make the
behavior obvious to users.
