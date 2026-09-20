# Lielz scripts port

Source: `docs/archive/lielz_scripts_04-2024.mpackage`, a personal Mudlet
script collection for Duris built up between 2015 and April 2024 (roughly 340
triggers, 1,080 aliases, 200 keys, 17 timers, 17 scripts). This records what
was carried into the package in 1.2.0, what was left out, and why.

This first pass took only display helpers. The automation in the archive
was left where it is for now; the list below is a starting point if any of
it is wanted later.

## Ported (display only)

| Archive feature | Where it landed | Notes |
| --- | --- | --- |
| Contact Capture (ship contacts parsed and colored by side, sorted) | SHIP tab, `renderShip` | Now also reads GMCP `Ship.Info`/`Ship.Contacts`, which the archive predates. Text parser kept as fallback. |
| Ship Docked / Undocked / disembark / Board / Set Captain / Set Max Speed / locked on / Target Cleared | ship state shown in SHIP tab | Timers that polled `look contacts` every 2 s were **not** ported; click the SHIP tab to refresh. |
| Deck / Guns / Repair skill gain notices | `[Ship] Guns skill +N` | |
| Damage Calculator Group + Damage Odometer aliases | DMG counter, `ui damage`, `ui damage reset` | Prefers `Combat.Update.round`; falls back to `[Damage: N]` lines. |
| Calculate Exp ("N or so more of those to level") | `[+N exp] … about K more like that` | Driven by GMCP `exp`/`tnl` instead of the `Experience till level` line. |
| Scan to Numbers (distance words to numbers, colored directions) | scan formatter | Per-direction summary replaces the archive's broadcast to the alliance channel. |
| Spells Out banners (sanc, rage, war cry, stone), Disarm banners, Icy Eye, Skill improved, Bard song banners, frost beacon, Tracks Report | alert banners | Archive versions that also sent chat messages or re-wielded a weapon were reduced to the banner. |
| GroupChecker `healcheck` (missing HP, moves coloring, weakest link) | group panel | Weakest player highlighted in red; "AutoVigTarget" selection dropped. |
| Chat Capture timestamp prefix | chat timestamps | |
| Keypad key group | numpad keys | Same layout as the archive (`+` down, `-` up). |

## Left out

- **Automation**: Auto Stand, Auto Group, Autorescue, Rebash, FleeStab,
  Botting, autoassist, Traps ("order followers kill"), Spam Timer, Scan
  Timer, Score Timer, Skill Practice timers, Roller (auto-rerolls stats),
  Exp gained looting, Pick up ore, Wands, Vit/Virtue casting, potion and
  corpse macros, Directions speedwalks. Not ported in this pass.
- **Channel broadcasts**: scan results, tracks, spell hits, ID strings, epic
  zone completions and arti lists were sent to `acc`/`gcc`. Anything that
  talks on a channel is out.
- **Arti Tracker** and **Epic Zone Checker**: hardcoded 2022 item and zone
  lists plus paging automation. Stale and guild-specific.
- **Board Checker**: cargo price watch with hardcoded expected prices.
- **Split tracker / bidscore**: loot-split dice system with a local database.
  Group-policy tooling, not UI.
- **Class key groups** (Healer, Skald, Necromancer, …): personal ability
  hotkeys.
- **GUI Monitor**: a fixed-pixel 1920x1200 layout. This package already has
  a percentage-based layout.
- **Active Spells capture**: GMCP `Char.Affects` already provides names and
  durations.
- **Prompt HP/move delta echo**: the GMCP vitals gauges cover it.
- **Blank-line gags around `<prompt>` tags**: this package does not use the
  server's terminal tag mode.
- **deleteOldProfiles**: profile housekeeping, unrelated to the UI.

## Verification

`python3 build.py --check` passes. No Mudlet runtime is available in the
build environment, so the new triggers were not exercised against live server
text. Regexes were taken from the archive as written and loosened where the
archive had duplicate variants. Import the package and run `scan`, a fight,
and a ship voyage to confirm; `ui set` can switch any piece off if a pattern
misfires.
