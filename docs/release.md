# Release Guide

mahjong release artifacts are generated from the version in `VERSION`.

## Local Dry Run

```bash
swift build
swift test
script/build_release_zip.sh
script/build_release_dmg.sh
```

Artifacts are written to `.build/dist/`:

- `mahjong-<version>-macos.zip`
- `mahjong-<version>-macos.dmg`

## Version Metadata

`script/build_app.sh` writes these bundle fields from the shared version source:

- `CFBundleShortVersionString`: `VERSION`
- `CFBundleVersion`: `MAHJONG_BUILD_NUMBER` or the git commit count

Override locally when needed:

```bash
MAHJONG_VERSION=0.5.1 MAHJONG_BUILD_NUMBER=42 script/build_release_zip.sh
```

## Signing

Local development builds are ad-hoc signed. For Developer ID signing, set:

```bash
export APPLE_DEVELOPER_ID_APPLICATION="Developer ID Application: Example, Inc. (TEAMID)"
script/build_app.sh
script/sign_app.sh .build/mahjong.app
```

Verify:

```bash
codesign --verify --deep --strict --verbose=2 .build/mahjong.app
```

## Notarization

Use either a notarytool keychain profile:

```bash
export NOTARYTOOL_KEYCHAIN_PROFILE=mahjong-notary
script/notarize.sh .build/dist/mahjong-0.5.0-macos.dmg
```

Or Apple ID credentials:

```bash
export APPLE_ID="developer@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="app-specific-password"
script/notarize.sh .build/dist/mahjong-0.5.0-macos.dmg
```

`script/notarize.sh` staples `.app` and `.dmg` artifacts after notarization.

## GitHub Release

The release workflow runs on tags that start with `v`, for example:

```bash
git tag v0.5.0
git push origin v0.5.0
```

The workflow runs tests, builds zip and dmg artifacts, uploads workflow
artifacts, and attaches them to the GitHub Release.

The current workflow builds unsigned release artifacts. Developer ID signing and
notarization require Apple credentials to be configured outside the repository.

## 1.0 Release Checklist

Use this checklist before tagging `v1.0.0`.

### P0 Verification

- [ ] `swift build` passes without new warnings.
- [ ] `swift test` passes.
- [ ] `script/build_release_zip.sh` creates `.build/dist/mahjong-1.0.0-macos.zip`.
- [ ] `script/build_release_dmg.sh` creates `.build/dist/mahjong-1.0.0-macos.dmg`.
- [ ] The `.app` launches, quits from the menu bar, and relaunches cleanly.
- [ ] Closing the Board hides the window without quitting the app.
- [ ] The pet and menu bar item can reopen the Board.
- [ ] Privacy mode hides task titles, summaries, model names, token values, token analytics totals, future-plan notes, and detailed diagnostic paths.
- [ ] Codex, Claude CLI, Claude Desktop, Hermes, ChatGPT Desktop, OpenClaw, terminal runtime, and desktop runtime diagnostics each show a clear enabled, disabled, missing path, no data, failed, or OK state.

### P1 Product Pass

- [ ] Board columns, Settings, Token Usage, Future Tasks, and Runtime list have useful empty states.
- [ ] Long titles, provider names, model names, and paths truncate without overlapping.
- [ ] Background refresh remains quiet during a 30-minute local run.
- [ ] README screenshots, showcase page, privacy notes, architecture notes, and provider-development docs match the release behavior.

### P2 Decision Log

- [ ] Decide whether Sparkle auto-update ships in 1.0 or moves to post-1.0.
- [ ] Check basic accessibility labels, keyboard reachability, and contrast.
- [ ] Confirm Chinese and English docs describe the same provider and privacy boundaries.
