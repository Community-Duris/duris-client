# Lielz scripts port

Source: `docs/archive/lielz_scripts_04-2024.mpackage`, a personal Mudlet
script collection for Duris built up between 2015 and April 2024 (roughly 340
triggers, 1,080 aliases, 200 keys, 17 timers, 17 scripts). This records what
was carried into the package, in which release, and what was left behind.

## Pass 1 (1.2.0): display helpers, into ArjUI

| Archive feature | Where it landed | Notes |
| --- | --- | --- |
| Contact Capture (ship contacts parsed and coloured by side, sorted) | SHIP tab, `renderShip` | Also reads GMCP `Ship.Info`/`Ship.Contacts`, which the archive predates. Text parser kept as fallback. |
| Ship docked/undocked/disembark/board/captain/max speed/lock-on | ship state in SHIP tab | |
| Deck / Guns / Repair skill gain notices | `[Ship] Guns skill +N` | |
| Damage Calculator + Damage Odometer | DMG counter, `ui damage`, `ui damage reset` | Prefers `Combat.Update.round`; falls back to `[Damage: N]` lines. |
| Calculate Exp | `[+N exp] ... about K more like that` | Driven by GMCP `exp`/`tnl`. |
| Scan to Numbers | scan formatter with per-direction summary | |
| Spells Out, Disarm, Icy Eye, Skill improved, Bard song, frost beacon, Tracks banners | alert banners | |
| GroupChecker `healcheck` | group panel: moves %, missing HP, weakest highlighted | |
| Chat Capture timestamp prefix | chat timestamps | |
| Keypad key group | numpad keys | |

## Pass 2 (1.3.0): automation and aliases, into ArjAuto

Everything below is off until switched on with `auto <name> on`. Character-specific
names in the archive (container "satchel", scroll "numbla", wand keywords, the bot
owners' names) became variables or were dropped.

| Archive feature | ArjAuto | Notes |
| --- | --- | --- |
| Auto Stand (takedowns, sweeps, quake, wall kick, mem/pray done) | `autoStand` | Same lines; "already down" and "immovable" banners kept. |
| Auto Group (consent lines, incl. pets) | `autoGroup` | Groups the last word of the consenting name. "Is in another group" tell kept. |
| Autorescue Group (terse + full hit lines, lag handling) | `autoRescue`, `rescue add|del|group|list|clear` | `MyAllies` became a persisted list; `rescue group` adds the current group. A 6 s safety unlock covers unmatched response lines. |
| autoassist (assist a group member who is attacked) | `autoAssist` | Uses GMCP group membership instead of the archive's captured list; `rage` on assist moved to `autoRage`. |
| AutoRage timer/trigger | `autoRage` | Re-rage 3 s after "rage abates" while fighting. The 12 s rage timer was dropped. |
| Disarm re-wield | `autoWield` + `wep` | |
| Exp gained loot, Pick up ore | `autoLoot`, `autoOre` | Uses the `container` variable. |
| Beckon follow/consent | `autoFollow` | |
| Bard Song Finished/Failed autoplay | `autoPlay` + `song` | |
| Traps (dim, shadow travel, entered game, wall bump) | `trapKill` | "order followers kill <first word>". |
| Scan reporting to alliance | `scanReport` + `report channel` | Report channel defaults to local echo. |
| Tracks / Spells Hit / Icy Eye / frost beacon / ship lock and sink reports | `eventReport` | |
| Rebash Group + aliases | `rbsh`, `rbsht`, `bof` | 13.99 s lag timer kept. Per-second countdown dropped. |
| FleeStab (return stab) | `fls`, `fls <target>` | One-shot; disarmed by failed-flee lines. |
| Bash Group racial shortcuts, trample | `bo bt bd ...`, `bh bb ...`, `tr` | Key clashes in the archive resolved: `bd` drow, `bw` dwarf, `bk` thri-kreen, `bm` minotaur. |
| Containers, Corpses, Misc, Movement aliases | same short names | Personal item aliases (`invis`, `tmp`, eq speakers) dropped. |
| Potions | `qf <item>`, `rq <item>` | Generic instead of one alias per potion. |
| Wands / `use_wand` | `uw <item> [target]`, `uwt`, `held` | |
| Set Variables | `tt ht container food wep held dd tank song cargo contra` | Pet and plane targets dropped. |
| vit_all / virtue_all | `castall <spell>`, `vitall`, `virtueall` | Iterates GMCP group members. `max vits` cap dropped. |
| Cleric "weakest link" helpers | `weakest` | Sets `healtarget` to the most hurt group member. |
| Spam Timer, Scan Timer | `spam <cmd>`/`spamon`/`spamoff`, `scan timer on|off` | Interval configurable; both idle-and-standing only. |
| Ships aliases and Ship key group | `oh os ff* ot* jet disem le..lw ship poll lout shipf shipn qkcargo qkreload`, `shipKeys` | Relative headings use the SHIP tab's locked contact. |
| Split tracker / bidscore | `split start|roll|free|scores|set|flush` | Mudlet DB replaced by the JSON file. |
| ID trigger group | `id <item>`, `idscroll` | Echoes locally; also reports when a channel is set. |
| Epic Zone Checker | `epic report` | Records completed zones from `epic zones` output; no polling timer. |
| Roller | `roller`, `roller threshold` | Stops itself when a keeper is found. |
| Startup commands | `login add|list|clear` | Nothing is sent by default. |
| Directions notes (planes) | `dirs <plane>` | Personal speedwalks to specific zones dropped. |
| Comm `locate` | `locate` | |

## Still in the archive only

- **Arti Tracker** and **Board Checker**: hardcoded 2022 item lists and cargo
  prices. Would need current data to be useful.
- **Class alias and key groups** (Anti-Paladin, Berserker, Paladin, Assassin,
  Cleric, Healer, Skald, Necromancer, ...): one-character ability hotkeys.
- **Bot People**: "tell <name> do <cmd>" remote control of specific characters.
- **Eq aliases**: speaker words and swaps for specific items.
- **TolmHints**: 2021 quest hint text sent to a channel.
- **GUI Monitor**: fixed 1920x1200 layout; this package is percentage-based.
- **Active Spells capture**, prompt delta echo, tag-mode blank-line gags:
  covered by GMCP or not applicable.
- **Score / Epic Zones / Look Contacts polling timers**: ship contacts polling
  is available as `ship poll`; the others were not carried.
- **deleteOldProfiles**: profile housekeeping.

## Verification

`python3 build.py --check` passes. No Mudlet runtime is available in the
build environment, so none of this was exercised against live server text.
Regexes were taken from the archive as written. Import the package and try
each toggle in a safe spot; every toggle can be switched off individually.
