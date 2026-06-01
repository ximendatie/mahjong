# Changelog

All notable changes to mahjong are documented here.

This project follows a simple release-note format:

- `Added` for new capabilities.
- `Changed` for behavior updates.
- `Fixed` for bug fixes.
- `Privacy/Safety` for local-data, permissions, and display-boundary changes.
- `Known Issues` for important unresolved limitations.

## Unreleased

### Added

- Nothing yet.

### Changed

- Nothing yet.

### Fixed

- Nothing yet.

### Privacy/Safety

- Nothing yet.

### Known Issues

- Signed and notarized releases require Apple Developer credentials configured outside the repository.

## 0.5.1 - 2026-06-01

### Added

- Dock entry for mahjong using the red Mahjong tile app icon.
- Stage 7 roadmap for 1.x ecosystem expansion and automatic-update planning.
- Provider scaffold and auto-update strategy docs for 1.x planning.

### Changed

- Release packaging now generates the Dock icon from `Resources/MahjongTiles/red.png` with either ImageMagick or macOS `sips`.
- Provider support issue template now captures permission model, safe sample shape, and data that must not be read or displayed.

### Fixed

- Release zip and dmg builds can run without sharing the same temporary iconset directory.

### Privacy/Safety

- Auto-update strategy keeps early 1.x on manual GitHub Releases until signing, notarization, and feed hosting are stable.

### Known Issues

- Signed and notarized releases require Apple Developer credentials configured outside the repository.
