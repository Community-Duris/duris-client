# Updates and upgrades: server and web-client study

Working log for improving the Arjinius Client Mudlet package by comparing it
against what the New Duris server actually sends and what the official web
client already does with that data.

Sources studied (all public, cloned read-only into a scratch dir on 2026-09-20):

- Server: https://github.com/Community-Duris/Duris
  - `src/net/gmcp.h`, `src/net/gmcp.c` (package list, send paths)
  - `src/core/json_utils.c` (exact JSON field names for each package)
  - `src/net/prompt.c` (prompt format the package's regex triggers depend on)
  - `src/net/chat_presentation.c`, `docs/guides/STRUCTURED_CHAT_COLORIZATION.md`
- Web app (website + browser client): https://github.com/Community-Duris/DurisWebApp
  - `frontend/src/types/mud.ts` (typed GMCP shapes)
  - `frontend/src/stores/mudStore.ts`, `components/mud/MudChatPanel.vue`,
    `MudAffects.vue`, `ShipRadar.vue`, `MudMap.vue`

Package studied: `duris-client.mpackage` v1 (two scripts: `ArjUI` 3084
lines, `ArjMapper` 1351 lines; no triggers/aliases/keys as XML items, all
created at runtime with `tempTrigger`/`tempAlias`).

---

## 1. What the server sends (ground truth)

Every GMCP package the server can emit, from `gmcp.h` and grep of `src/`:

| Package | Sent when | Package uses it? |
|---|---|---|
| `Char.Vitals` | HP/mana/move change, group vitals | Yes |
| `Char.Status` | Login, level change (self only) | Partially |
| `Char.Affects` | Affect added/removed/expired | Yes |
| `Room.Info` | Room entry, dirty-room flush | Yes |
| `Room.Map` | Wilderness zones only (ASCII map) | Yes (mapper) |
| `Combat.Update` | Each round, target change, combat end (`{"target":null}`) | Yes |
| `Comm.Channel` | say, tell, gcc, gsay, nchat, jchat, petition, wizmsg | Partially |
| `Group.Status` | Group join/leave/update | Yes |
| `Quest.Status` | Login, quest accept/progress/complete | **No** |
| `Quest.Map` | Once per session when a quest map was bought | **No** |
| `Ship.Contacts` | Periodic flush while on a ship bridge | **No** |
| `Ship.Info` | Periodic flush, slow-changing ship data | **No** |
| `Core.AuthChallenge` | Only for DurisWeb service auth | N/A |

Packages the client registers handlers for that the server **never sends**:
`Group.Update`, `Combat.Status`. `Char.Skills` and `Char.Items` are defined in
`gmcp.h` but have no send path anywhere in `src/`.

The server ignores `Core.Supports.Set` entirely. It only parses `Core.Hello`
and `Client.Info` (records `client` and `version` strings). Every package is
sent unconditionally to any GMCP-negotiated descriptor unless the player has
toggled GMCP off (`PLR3_NOGMCP`, via the player toggle command).

### Exact field names

**Char.Vitals**: `hp, maxHp, mana, maxMana, move, maxMove, exp, tnl, platinum,
gold, silver, copper, position, fighting (string|null), usesMana (bool)`.
`position` is one of `on your ass, sitting, kneeling, standing`.

**Char.Status** (self only): `name, level, class, race, alignment
(good|evil|neutral), guild, title`. Sent from `nanny.c` on character entry and
`limits.c` on level change.

**Char.Affects**: array of `{name, id, duration (seconds), icon}`. `icon` is
always the literal `"shield"`. No buff/debuff flag; the web client classifies
by keyword the same way this package does.

**Room.Info**: `num` (0 in wilderness), `name`, `colored_name`, `area`,
`colored_area`, `environment` (string), `coords {x,y,z}` (empty in
wilderness), `exits {n: vnum | true}`, `doors {n: {name, closed, locked}}`,
`players [{name}]`, `npcs [{name, colored_name, vnum, keyword, fighting?}]`,
`items [{name, colored_name, vnum}]`, `zone` (number), `terrain` (number).
`npcs[].fighting` is `"you"`, a player name, an NPC short desc, `"someone"`, or
`"someone who has already left"`.

**Combat.Update**: `target {name, health, healthPercent, position}` plus
optional `round {attacker, damage, damageType, critical}`. There is **no
`tank` field**; the package's tank tracking from GMCP is dead code and it relies
entirely on the prompt regex. `health` strings: `excellent, few scratches,
small wounds, quite a few wounds, big nasty wounds, pretty hurt, awful,
bleeding to death`. Target `position` uses `on their ass`.

**Comm.Channel**: `channel, sender, text, timestamp`, optional `alignment`
(nchat/jchat only: good|evil|undead|neutral), optional `presentation` (v1
structured colour runs for say/tell/gcc). Channel strings actually emitted:
`say`, `tell`, `gcc` (guild), `gsay` (group), `nchat`, `jchat`, `petition`,
`wizmsg`. Outgoing tells arrive with `sender = "You -> Name"`.

**Group.Status**: `members [{name, level, class|null, race|null, hp, maxHp,
move, maxMove, position, rank (head|front|back), isNpc, inRoom, targetNum,
targetKeyword}], size, maxSize`.

**Quest.Status**: `active, type (ask|kill|null), target, remaining, killCount?,
killRequired?, mapBought, zoneNumber?`.

---

## 2. Findings: mismatches and gaps in the package

Ordered by user impact.

### F1. Guild chat never reaches the GUILD tab (bug)
Server channel name for guild chat is `gcc`. The package routes only `guild`
and `clan` to the guild box. Guild chat therefore only appears in ALL.
*Fix: route `gcc` to the guild tab.*

### F2. Login detection depends on a specific prompt layout (fragile)
`renderAll()` and the silent `time` query fire from a regex on
`^< \d+h/\d+H \d+v/\d+V Pos:`. Any player whose prompt omits max HP, max moves
or the Pos element never triggers it. The server sends `Char.Status` exactly
once on character entry, which is a reliable, prompt-independent login signal.
*Fix: also treat the first `Char.Status` after connect as login.*

### F3. Char.Status data is thrown away
Level, class, race, guild and title are received but only `name`/`alignment`
are read. The STATS tab shows only vitals and says "click tab to send stat".
*Fix: show level/class/race/guild in the STATS tab.*

### F4. Coins, fighting target, and usesMana ignored
`Char.Vitals` carries all four coin types and `usesMana`. Non-mana classes
still see an MP bar reading 0/0.
*Fix: show coins in STATS; relabel the mana gauge for non-mana classes.*

### F5. Quest.Status ignored
The web client shows a quest line (type, target, kill count, remaining). The
package has nowhere for it.
*Fix: add a quest line to the STATS tab.*

### F6. NPC `fighting` field ignored
The mobs list cannot show which mob is attacking you or a groupmate. The web
client marks these.
*Fix: annotate mobs list with `[vs you]` / `[vs Name]`.*

### F7. Doors ignored
`Room.Info.doors` gives closed/locked state per exit. Exit buttons show every
exit identically.
*Fix: style exit buttons differently when the door is closed.*

### F8. Group panel ignores `inRoom`, `size/maxSize`, move
Members not in the room look identical to those present.
*Fix: header shows `n/max`; absent members are dimmed and tagged.*

### F9. nchat alignment ignored
Server tags nchat/jchat with the speaker's race-war alignment; the web client
colours the sender by it.
*Fix: colour nchat sender by alignment.*

### F10. Unrouted channels
`petition`, `wizmsg`, `jchat` fall through to ALL only with a generic grey
colour. The web client groups petition+wizmsg into a "God" tab.
*Fix: give them distinct colours; jchat routes with nchat.*

### F11. Dead code and wasted work
- Handlers for `gmcp.Group.Update` and `gmcp.Combat.Status` never fire.
- `sysDataSendRequest` re-renders target and tank on every command sent.
- `Core.Supports.Set` is sent but ignored by the server (harmless, keep for
  forward compatibility).
- `conditionToPercent` checks `nasty wounds` before `big nasty`, so
  `big nasty wounds` maps to 50 instead of 40. Only matters for the
  prompt-derived tank bar, since Combat.Update provides `healthPercent`.
*Fix: remove the two dead handlers, fix the ordering.*

### F12. Player alignment colouring in the PLAYERS list mostly cannot work
`Room.Info.players` only carries `name`, and `Char.Status` is only sent for
self. So alignment colouring only ever knows your own alignment. This needs a
server change (add alignment to `Room.Info.players`), which is out of scope
for a client package. Left as is; noted for upstream.

### F13. Ship radar (large feature, not done)
`Ship.Contacts` and `Ship.Info` give everything the web client's ShipRadar
draws (contacts with bearing/range/heading, armor, weapons, cargo). A Geyser
radar panel is feasible but is a separate project. Recorded here as the
biggest untapped data source.

### F14. Structured chat presentation (not done)
`Comm.Channel.presentation` gives exact colour runs for say/tell/gcc so a
client can render the line identically to the terminal. The package currently
strips colours and applies its own per-channel colour. Adopting `presentation`
would need a BGR-index to RGB mapping. Deferred.

---

## 3. Implementation log

Package version bumped `1` to `1.1`. Changes are all inside the `ArjUI` script.

- [x] F1: `gcc` routes to GUILD tab.
- [x] F2: first `Char.Status` after connect triggers login render.
- [x] F3: STATS tab shows name, level, class, race, guild.
- [x] F4: STATS tab shows coins; mana gauge reads "No Mana" for `usesMana=false`.
- [x] F5: STATS tab shows quest status; `Quest.Status` handler added.
- [x] F6: mobs list tags NPCs by their `fighting` value.
- [x] F7: exit buttons use a distinct style when the door is closed.
- [x] F8: group header shows `n/max`; members not in room are dimmed.
- [x] F9: nchat/jchat sender coloured by alignment.
- [x] F10: petition/wizmsg/jchat colours; jchat routes to NCHAT tab.
- [x] F11: dead handlers removed; `big nasty` ordering fixed. The
      `sysDataSendRequest` re-render was left in place (cheap, and it keeps the
      prompt-derived tank bar fresh).
- [x] `Core.Hello` version string follows package version (`ArjUI.VERSION`).
- [x] Repacked with `zip -r -0`; XML validated as well-formed and the embedded
      script round-trips byte-for-byte; Lua passes `luac -p`.

Notes from implementation:

- `Quest.Status.remaining` is the number of bartender quests the player may
  still take today (`sql_world_quest_can_do_another`), not a timer. The
  STATS line says "(N more today)".
- `config.lua` uses CRLF line endings. Keep them when editing.
- The `<Script>` element in the XML uses `isActive="yes" isFolder="no"`, not
  `"1"`/`"0"`. Any re-embedding script must match that.
- Group members with `isNpc=true` get a trailing `*`; members with
  `inRoom=false` are dimmed and their position slot reads `[AWAY]`.

Not verified in a running Mudlet (no Mudlet in this environment). Everything
changed is data-driven from fields confirmed in the server source; the risk
is in Geyser layout only. Import into Mudlet and run through
`docs/MUDLET_SMOKE_TEST.md` sections that apply before release.

## 3b. Source/assembly split (2026-09-20)

The package is now built from `src/` by `build.py` instead of being edited in
place. Motivation: the first round of changes above had to be regexed into the
XML inside the zip by hand, with three separate gotchas (CRLF `config.lua`,
`isActive="yes"` attribute form, XML escaping). The build handles all of them
and was verified to reproduce the hand-assembled XML byte for byte (same CRC).

- `VERSION` is the single version source; the build writes it into
  `config.lua` and `ArjUI.VERSION`.
- `python3 build.py --check` runs `luac -p` on both scripts.
- The built `.mpackage` stays committed at the repo root so the install path
  in the README keeps working.

## 4. Next candidates

1. Ship radar panel (F13).
2. `presentation`-based chat rendering (F14).
3. Ask upstream to add `alignment` to `Room.Info.players` (F12).
4. Use `Room.Info.environment` to tint the room header by terrain.
