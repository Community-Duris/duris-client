# Changelog

Notable changes to the Duris Client Mudlet package. Versions follow [Semantic Versioning](https://semver.org) (`MAJOR.MINOR.PATCH`); see [docs/RELEASING.md](docs/RELEASING.md) for what each part means here. Each version heading must match `VERSION`; the release workflow copies that section into the GitHub Release notes.

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
