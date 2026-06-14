# mahjong Intro Video Design

## Style Prompt

A calm, local-first macOS product film for mahjong: a quiet desktop companion that turns scattered AI agent activity into one readable signal. The visual language should inherit the existing showcase: warm ivory canvas, thin grid structure, oversized black Chinese typography, Mahjong red, teal status dots, and restrained technical overlays. It should feel precise, trustworthy, and useful rather than loud or promotional.

## Colors

- Canvas: `#F4EFE5`
- Ink: `#151712`
- Muted text: `#5E665C`
- Hairline: `#D8D2C4`
- Mahjong red: `#D94238`
- Status teal: `#0F9A81`
- Deep green: `#09251F`

## Typography

- Statement voice: `MahjongStatement`, a local `Songti SC` alias, serif for the largest Chinese headlines.
- Interface voice: `MahjongUI`, a local `PingFang SC` alias, sans-serif for body and UI labels.
- Telemetry voice: `IBM Plex Mono`, `JetBrains Mono`, monospace only for short status counts and interface badges, never for code, commands, or local paths.

## Motion

- Primary transition: focus-pull blur crossfade, 0.65-0.8s.
- Entrances start 0.16-0.28s after scene reveal and vary between y, x, scale, blur, and line growth.
- Ambient motion is slow and finite: tile drift, status pulse, board scan line, and grid glides.
- No jump cuts. No per-element exit animations before transitions; transitions handle scene changes.

## What NOT to Do

- Do not use dark neon cyber styling, purple/blue gradients, or generic SaaS card grids.
- Do not imply mahjong uploads data, controls provider apps, or reads full conversations by default.
- Do not show source code, command-line snippets, local file paths, session IDs, JSONL, or implementation details in the video.
- Do not use overly playful Mahjong/game visuals; the product is a desktop work companion.
- Do not use Inter, Roboto, Noto Sans, or other banned default web fonts.
