# AGENTS.md

Guidance for AI agents working in this repo. `CLAUDE.md` and `GEMINI.md` are symlinks to this file.

## What this is
A **Mudlet client package** (UI only) for the MUD *New Duris*. Upstream: https://github.com/Community-Duris/duris-client (originally by Arjinius).

## Layout
- `src/` — **the source of truth.**
  - `src/scripts/ArjUI.lua`, `src/scripts/ArjMapper.lua` — the two Mudlet scripts (all UI + mapper Lua).
  - `src/package.xml` — Mudlet XML skeleton. Each `<script>` body is a `@@SCRIPT:<Name>@@` placeholder filled from `src/scripts/<Name>.lua`.
  - `src/config.lua` — package metadata; its `version` line is overwritten at build time.
  - `src/assets/` — files copied into the zip verbatim (`NewDuris v1.png`, `.mudlet/Icon/ArjUI.jpeg`).
- `VERSION` — the package version. The build writes it into `config.lua` and into `ArjUI.VERSION`.
- `build.py` — assembles the package (stdlib Python only). `python3 build.py --check` only syntax-checks the Lua.
- `duris-client.mpackage` — **build output**, committed so users can download it. Never hand-edit it.
- `README.md` — user-facing install docs. `docs/` — reference material and the ongoing-projects log.

## Working on the package
- Edit `src/`, then run `python3 build.py`. Commit the rebuilt `.mpackage` together with the source change.
- Bump `VERSION` when changing the package. Do not edit `version` in `src/config.lua` or `ArjUI.VERSION` by hand.
- Keep XML well-formed; the build validates it. Lua gets XML-escaped automatically, so write plain Lua.
- Requires **Mudlet 4.19.1+** and **GMCP**. Use Mudlet/Geyser APIs; do not introduce external Lua deps.
- Server ground truth for GMCP field names is documented in `docs/ongoing-projects/updates-upgrades.md`.

## Constraints
- Client-side UI only. Never add gameplay automation, bots, or anything that gives unfair advantage.
- Keep the dark-fantasy aesthetic and percentage-based scaling consistent.
- No runtime tests exist; `build.py --check` is syntax only. Verify behaviour by importing the package into Mudlet.

## Git
- Commit only when asked. Keep commits small and describe what changed in the XML/Lua.
