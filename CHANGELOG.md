# Changelog

Notable changes to the Duris Client Mudlet package. Each version heading must match `VERSION`; the release workflow copies that section into the GitHub Release notes.

## 1.1 - 2026-09-20

First tagged release.

- Aligned ArjUI with the New Duris server's GMCP output (`Char.Status`, `Char.Vitals`, room, group, and combat fields).
- Split the package into editable sources under `src/` with a stdlib-only `build.py` assembler.
- Renamed the build output to `duris-client.mpackage`.
- Added GitHub Actions: CI syntax-checks and builds on every push; pushing a `v*` tag publishes a release with the package attached.
- Refreshed the README with install steps, an architecture overview, and troubleshooting.

## 1.0

Original Arjinius Client package by Arjinius, as uploaded to the repository.
