# Changelog

Notable changes to the Duris Client Mudlet package. Versions follow [Semantic Versioning](https://semver.org) (`MAJOR.MINOR.PATCH`); see [docs/RELEASING.md](docs/RELEASING.md) for what each part means here. Each version heading must match `VERSION`; the release workflow copies that section into the GitHub Release notes.

## 1.2.0 - 2026-09-20

Display helpers ported from the community "lielz scripts" collection (`docs/archive/lielz_scripts_04-2024.mpackage`). Everything is client-side display; no gameplay automation was carried over. Details in `docs/ongoing-projects/lielz-port.md`.

- **SHIP tab**: contacts sorted by range and colored by side, heading and speed, captain, max speed, lock-on target, and sailing skill gains. Reads GMCP `Ship.Info`/`Ship.Contacts` when present and the `look contacts` text otherwise. First step toward the ship radar noted in the server study.
- **Damage counter** in the target panel: per-fight total that resets when a kill or experience share arrives, plus a session report with damage per second (`ui damage`, `ui damage reset`, or click the counter). Uses `Combat.Update.round` or `[Damage: N]` lines, never both.
- **Experience notices**: `[+N exp] M to level, about K more like that` from GMCP `exp`/`tnl`. The TNL bar shows the last gain.
- **Scan formatter**: `scan` lines become `[E ] 2  A Drow Elf` with distance and direction colored, followed by a per-direction summary.
- **Alert banners** for sanctuary, hellfire, stone skin, heroism, rage, and war cry dropping; being disarmed, dropping your weapon, disarm results; being scryed; skill improvements; song finished or failed; frost beacons; and tracks.
- **Group panel**: moves percentage per member colored by how spent it is, HP as `cur/max -missing`, and the most hurt player in the room highlighted.
- **Chat timestamps** (`hh:mm`) on every chat line.
- **Numpad movement keys**: 8/2/4/6, 7/9/1/3, `-` up, `+` down, 5 look, `/` scan, 0 flee.
- **Settings**: `ui set` lists six toggles, all on by default and persisted to `arjui_settings.json`. `ui help` lists commands.
- `ui debug` also reports `Ship.Info` and `Ship.Contacts`.

## 1.1.0 - 2026-09-20

Same package as 1.1, re-released to adopt semantic versioning.

- Versions are now `MAJOR.MINOR.PATCH`. The build and the release workflow reject anything else.
- `build.py` creates the output directory when it is missing.

## 1.1 - 2026-09-20

First tagged release.

- Aligned ArjUI with the New Duris server's GMCP output (`Char.Status`, `Char.Vitals`, room, group, and combat fields).
- Split the package into editable sources under `src/` with a stdlib-only `build.py` assembler.
- Renamed the build output to `duris-client.mpackage`.
- Added GitHub Actions: CI syntax-checks and builds on every push; pushing a `v*` tag publishes a release with the package attached.
- Refreshed the README with install steps, an architecture overview, and troubleshooting.

## 1.0

Original Arjinius Client package by Arjinius, as uploaded to the repository.
