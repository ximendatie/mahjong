# Contributing

Thanks for helping make mahjong more useful. The project is small on purpose:
local observation, clear privacy boundaries, and fast iteration.

## Development Setup

Requirements:

- macOS 14 or newer
- Swift 6 toolchain
- ImageMagick, optional, if you want `script/build_app.sh` to regenerate icons

Common commands:

```bash
swift build
swift test
script/build_and_run.sh
```

## Pull Request Checklist

- Keep provider behavior local-first and read-only.
- Do not upload local session data or send it to remote services.
- Do not write to provider configuration, session, or cache files.
- Avoid showing full conversation bodies by default.
- Add or update tests for parser and state inference changes.
- Update `README.md` or `docs/architecture.md` when user-visible behavior or
  provider behavior changes.

## Adding a Provider

Start with [docs/provider-development.md](docs/provider-development.md). In
short:

1. Add an `AgentTaskProvider` when you can safely derive task cards from local
   metadata.
2. Add an `AgentRuntimeProvider` when you can detect whether an app or process
   is running.
3. Prefer explicit metadata, timestamps, and status events over parsing message
   content.
4. Treat missing files, unknown schemas, and permission failures as empty data
   instead of app-breaking errors.
5. Include fixture-based tests with representative local files or rows.

Good starter tasks are tracked in [docs/contributor-tasks.md](docs/contributor-tasks.md).

## Reporting Security or Privacy Issues

Please avoid posting sensitive local paths, prompts, session files, or database
contents in public issues. Use the guidance in `SECURITY.md`.
