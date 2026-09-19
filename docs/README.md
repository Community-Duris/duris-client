# docs/

Reference material copied from the sibling project **LuminariGUI**
(`~/projects/LuminariGUI/docs/`), a Mudlet UI package for a different MUD.
These files were copied verbatim and have **not** been adapted for the Duris
client yet. Treat them as background reading, not as a description of this
repo.

| File | Why it is here | What does NOT apply here |
|---|---|---|
| `MUDLET_COMPATIBILITY.md` | Version-by-version breakdown of Mudlet 4.19 → 4.22 changes (Qt6, stylesheet, label-callback, protocol-settings, resize events) and a triage checklist. Mostly Mudlet-generic. | Anything about MSDP. New Duris uses **GMCP**. |
| `MUDLET_DEVELOPMENT.md` | The "General Mudlet Development Best Practices" section onward: namespaces, Geyser/Qt stylesheets, label callbacks, resize handling, GMCP integration, package lifecycle, error handling. | The "Project Architecture" section at the top (`theGUI/` fragment build system, `build.py`, `package.py`). This repo edits `Arjinius Client.xml` inside the `.mpackage` directly. |
| `MUDLET_SMOKE_TEST.md` | Template for a manual real-Mudlet release checklist and result vocabulary (`PASS` / `FAIL-PACKAGE` / `UPSTREAM-BLOCKED`). | The specific checklist items, MSDP steps, and the GitHub Xvfb job. |
| `RESOURCE_LIFECYCLE.md` | Pattern for owning anonymous event handlers and temp timers so package uninstall / profile reset cleans up properly. | The `GUI.registerOwnedHandler` / `GUI.setOwnedTimer` helpers and audit scripts do not exist in this package. |
| `DEBUGGING.md` | Pattern for a single master debug flag with prefixed console trace lines. | The `GUI.DEBUG` flag and `00_debug.xml` fragment are LuminariGUI-only. |

Not copied (LuminariGUI-specific tooling): `CI.md`, `COVERAGE.md`,
`PYTHON_TOOLS.md`, `LUA_STATIC_ANALYSIS.md`, `SOUND_USAGE.md`,
`PROTOCOL_REFERENCE.md` (MSDP for LuminariMUD), changelogs, and
`ongoing-projects/`.
