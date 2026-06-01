# Provider Scaffold

Use this checklist when adding or reviewing a new mahjong provider. Keep the
first PR small: runtime detection only is a valid starting point.

## Files To Touch

| Area | File |
| --- | --- |
| Provider implementation | `Sources/Services/<Provider>LocalProvider.swift` |
| Provider descriptor | `Sources/Models/ProviderSettings.swift` |
| Store registration | `Sources/Stores/AgentTaskStore.swift` |
| Fixture tests | `Tests/MahjongTests/ProviderFixtureTests.swift` or a focused provider test |
| User docs | `README.md`, `README.zh-CN.md`, `docs/privacy.md` |

## Implementation Checklist

- [ ] Choose the smallest useful initial scope: runtime, task metadata, or both.
- [ ] Read only local files, local databases, process lists, or app runtime state.
- [ ] Return empty results for missing paths, unsupported schemas, or permission
  failures instead of crashing.
- [ ] Normalize records into `AgentTask` or `AgentRuntime` with stable IDs.
- [ ] Avoid displaying full conversation bodies by default.
- [ ] Add fixture coverage for normal, missing-field, and stale/inactive cases.
- [ ] Update Provider Diagnostics expectations if the provider has special
  permissions or known no-data states.

## Descriptor Template

```swift
AgentProviderDescriptor(
    id: .example,
    displayName: "Example",
    defaultEnabled: true,
    dataPaths: ["\(home)/.example/sessions"],
    privacyDescription: "Reads Example local session metadata such as status and timestamps.",
    detail: "Reads local Example session metadata."
)
```

## Out Of Scope For Provider PRs

- Sending messages or commands to the provider.
- Uploading session data.
- Reading API keys, secrets, attachments, or full conversation bodies.
- Adding broad UI redesigns alongside parser work.
