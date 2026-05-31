# Contributor Task Board

This document tracks good first issues and help-wanted tasks for the 0.4.x contributor-growth phase. Convert these entries into GitHub issues as maintainers are ready to triage them.

## Good First Issues

| Title | Labels | Suggested files | Acceptance |
| --- | --- | --- | --- |
| Add last refresh time to Diagnostics header | `good first issue`, `ui`, `diagnostics` | `Sources/Stores/AgentTaskStore.swift`, `Sources/Views/SettingsView.swift` | Settings shows one clear "last refreshed" timestamp for diagnostics. |
| Add clearer empty states for task columns | `good first issue`, `ui` | `Sources/Views/TaskColumnView.swift` | Empty running/completed/interrupted/history columns explain what the state means. |
| Document ChatGPT Accessibility behavior | `good first issue`, `docs`, `privacy` | `docs/privacy.md`, `README.md`, `README.zh-CN.md` | Docs explain why Accessibility is optional and that conversation text is not read. |
| Add one parser edge-case fixture | `good first issue`, `tests`, `parser` | `Tests/MahjongTests/*Tests.swift` | A provider parser covers a missing/partial field case without crashing. |
| Add Provider support matrix to README | `good first issue`, `docs`, `provider` | `README.md`, `README.zh-CN.md` | README table distinguishes task metadata, runtime detection, and required permissions. |

## Help Wanted Provider Tasks

| Provider | Initial scope | Labels | Notes |
| --- | --- | --- | --- |
| Gemini CLI | Process detection plus safe local metadata if available | `help wanted`, `provider`, `privacy` | Start with runtime detection if metadata format is unclear. |
| Aider | Local session or process detection | `help wanted`, `provider`, `parser` | Confirm local paths before parsing. |
| OpenCode | Local session or process detection | `help wanted`, `provider`, `parser` | Keep first PR narrow. |
| Cursor | Desktop runtime detection | `help wanted`, `provider`, `ui` | No project content parsing in the first version. |
| Windsurf | Desktop runtime detection | `help wanted`, `provider`, `ui` | No project content parsing in the first version. |
| Goose | Safe local metadata review | `help wanted`, `provider`, `privacy` | Document paths before implementation. |
| Continue | Safe local metadata review | `help wanted`, `provider`, `privacy` | Document paths before implementation. |

## Issue Template For Provider Work

```markdown
## Goal
Add initial support for <Provider> while keeping mahjong local-first and read-only.

## Initial scope
- [ ] Identify local data paths or runtime signal.
- [ ] Document what data is read.
- [ ] Implement the smallest useful task or runtime provider.
- [ ] Add fixture tests.
- [ ] Update README and privacy docs.

## Out of scope
- Sending messages or controlling <Provider>.
- Uploading local data.
- Displaying full conversation bodies by default.

## Acceptance
- `swift test` passes.
- Missing files or permissions do not crash the app.
- User-facing docs explain the provider behavior.
```
