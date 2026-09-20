# Releasing

Releases are published by GitHub Actions (`.github/workflows/release.yml`) when a version tag is pushed. The workflow rebuilds the package from the tagged sources, so the release asset always corresponds to the tag.

## Cut a release

1. Bump `VERSION` (for example `1.2`). Do not edit `src/config.lua` or `ArjUI.VERSION` by hand.
2. Add a `## 1.2 - YYYY-MM-DD` section to `CHANGELOG.md`. Its heading must equal `VERSION` exactly; the workflow copies that section into the release notes.
3. Rebuild and commit everything together:

   ```bash
   python3 build.py
   git add VERSION CHANGELOG.md duris-client.mpackage src
   git commit -m "Release 1.2"
   git push origin master
   ```

4. Tag and push the tag:

   ```bash
   git tag -a v1.2 -m "Duris Client 1.2"
   git push origin v1.2
   ```

5. Watch the run under **Actions → Release**. When it finishes, the release appears at <https://github.com/Community-Duris/duris-client/releases> with:
   - `duris-client.mpackage` (stable name; the README download badge points at the latest release)
   - `duris-client-1.2.mpackage` (versioned copy)
   - `SHA256SUMS.txt`

The workflow fails if the tag does not match `VERSION`. Fix `VERSION`, rebuild, commit, delete the bad tag (`git push --delete origin v1.2 && git tag -d v1.2`), and tag again.

## Redo a release

Delete the GitHub Release and the tag, then repeat step 4:

```bash
gh release delete v1.2 --yes
git push --delete origin v1.2
git tag -d v1.2
```
