# Releasing

## Version numbers

Versions follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`, tagged as `vMAJOR.MINOR.PATCH`. `build.py` and the release workflow reject any other shape. Mudlet does not interpret the string, so the meaning is a project convention:

| Bump | When |
| --- | --- |
| **MAJOR** | Players must reinstall or reconfigure: layout rebuilt, saved settings or aliases incompatible, package renamed, minimum Mudlet version raised. |
| **MINOR** | New panels, commands, or mapper features; behaviour changes that do not break an existing install. |
| **PATCH** | Bug fixes, GMCP field corrections, visual tweaks, docs inside the package. |

Pre-release tags such as `v2.0.0-rc.1` are not supported by the workflow; cut them as ordinary patch releases if needed.

## How it works

Releases are published by GitHub Actions (`.github/workflows/release.yml`) when a version tag is pushed. The workflow rebuilds the package from the tagged sources, so the release asset always corresponds to the tag.

## Cut a release

1. Bump `VERSION` (for example `1.2.0`) following the table above. Do not edit `src/config.lua` or `ArjUI.VERSION` by hand.
2. Add a `## 1.2.0 - YYYY-MM-DD` section to `CHANGELOG.md`. Its heading must equal `VERSION` exactly; the workflow copies that section into the release notes.
3. Rebuild and commit everything together:

   ```bash
   python3 build.py
   git add VERSION CHANGELOG.md duris-client.mpackage src
   git commit -m "Release 1.2.0"
   git push origin master
   ```

4. Tag and push the tag:

   ```bash
   git tag -a v1.2.0 -m "Duris Client 1.2.0"
   git push origin v1.2.0
   ```

5. Watch the run under **Actions → Release**. When it finishes, the release appears at <https://github.com/Community-Duris/duris-client/releases> with:
   - `duris-client.mpackage` (stable name; the README download badge points at the latest release)
   - `duris-client-1.2.0.mpackage` (versioned copy)
   - `SHA256SUMS.txt`

The workflow fails if the tag does not match `VERSION`. Fix `VERSION`, rebuild, commit, delete the bad tag (`git push --delete origin v1.2.0 && git tag -d v1.2.0`), and tag again.

## Redo a release

Delete the GitHub Release and the tag, then repeat step 4:

```bash
gh release delete v1.2.0 --yes
git push --delete origin v1.2.0
git tag -d v1.2.0
```
