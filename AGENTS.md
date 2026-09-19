# AGENTS.md

Guidance for AI agents working in this repo. `CLAUDE.md` and `GEMINI.md` are symlinks to this file.

## What this is
A **Mudlet client package** (UI only) for the MUD *New Duris*. Upstream: https://github.com/Community-Duris/duris-client (originally by Arjinius).

## Layout
- `Arjinius Client.mpackage` — the deliverable. A **zip** (stored, no compression) containing:
  - `Arjinius Client.xml` — all triggers, aliases, scripts, timers, keys (Mudlet XML export). This is the real source.
  - `config.lua` — package metadata (name, author, icon, description, version).
  - `.mudlet/Icon/ArjUI.jpeg`, `NewDuris v1.png` — assets.
- `README.md` — user-facing install docs.

## Working on the package
- Do not hand-edit the binary. Extract to a scratch dir, edit, then repack with `zip -r -0` (stored) so Mudlet reads it.
- Lua code lives inside `<script>` elements of the XML. Keep XML well-formed and preserve Mudlet's escaping.
- Requires **Mudlet 4.19.1+** and **GMCP**. Use Mudlet/Geyser APIs; do not introduce external Lua deps.
- Bump `version` in `config.lua` when changing the package.

## Constraints
- Client-side UI only. Never add gameplay automation, bots, or anything that gives unfair advantage.
- Keep the dark-fantasy aesthetic and percentage-based scaling consistent.
- No tests or build tooling exist; verify changes by importing the package into Mudlet.

## Git
- Commit only when asked. Keep commits small and describe what changed in the XML/Lua.
