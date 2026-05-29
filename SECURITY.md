# Security Policy

AgentsPet observes local agent activity and should stay conservative about user
data. Please report issues that could expose private prompts, session metadata,
local paths, or provider files beyond the app's documented behavior.

## Supported Versions

The project is pre-1.0. Security fixes target the default branch until release
branches exist.

## Reporting a Vulnerability

Please do not include private session files or full conversation contents in a
public issue. Open a minimal issue describing the risk, affected provider, and
safe reproduction steps. If a private contact channel is added later, this file
will be updated.

## Data Handling Expectations

- Local observation should remain read-only.
- Provider config, session, and cache files should not be modified.
- Conversation bodies should not be displayed by default.
- Remote network calls should not be added without explicit documentation,
  user control, and review.
