---
name: release
description: Cut a DevSweep release or fix the release pipeline - the release pull request, the published assets, the Sparkle appcast, the Homebrew cask or the npx installer. Use when asked to publish a version, when a release workflow fails, or when auto-update doesn't offer a new version.
---

# Release DevSweep

One-time account and token setup (signing key, Codecov, CodeRabbit, Homebrew tap, npm) is in
[`docs/MAINTAINING.md`](../../../docs/MAINTAINING.md), not here.

## How a release happens

1. Commits on `main` follow Conventional Commits (`feat:`, `fix:`, `perf:`, `deps:`; `feat!:` or a `BREAKING CHANGE:` footer for a major).
2. `.github/workflows/release.yml` runs release-please on every push to `main`, which keeps a "chore(main): release x.y.z" pull request updated with `version.txt`, `.release-please-manifest.json` and `CHANGELOG.md`.
3. **Merging that pull request** creates the `vX.Y.Z` tag and the GitHub release with the changelog. The rest of the workflow then:
   - runs the tests;
   - builds a universal app (`UNIVERSAL=1 scripts/build-app.sh`) with the version from release-please;
   - runs `scripts/package-release.sh`: zip, SHA-256, Sparkle `sign_update` signature and `appcast.xml` with the release notes;
   - generates an SPDX SBOM and signs the zip and SBOM with Sigstore (keyless, via the workflow's OIDC identity);
   - uploads everything to the release, including a copy of the zip under the stable name `DevSweep.zip` that the Homebrew cask points at;
   - publishes the npm installer, skipped with a notice when `NPM_TOKEN` is absent.
4. Installed apps check `https://github.com/<owner>/DevSweep/releases/latest/download/appcast.xml` once a day, show an update card with a changelog link, and install after Sparkle verifies the signature.

So: to release, review and merge the release pull request. Nothing else is manual.

## Republishing the assets of an existing tag

When a release exists but its assets are missing or wrong (a build that failed, for example):

```bash
gh workflow run release.yml -f tag=v0.1.0
```

It checks out that tag, rebuilds and re-uploads with `--clobber`.

## Troubleshooting

- **No release pull request.** Either there are no `feat`/`fix`/`perf`/`deps` commits since the last release, or Actions isn't allowed to create pull requests (Settings → Actions → General).
- **The first release proposes 1.0.0.** Without a previous release, release-please falls back to its default. `initial-version` in `release-please-config.json` decides it.
- **Release published without `appcast.xml`.** `SPARKLE_PRIVATE_KEY` is missing; the packaging step logs a warning. Fix the secret and re-run the workflow for that tag.
- **Installed apps never offer the update.** Check that `Resources/sparkle-public-key.txt` was committed before the build (without it `Updater.isEnabled` is false and Settings says the build can't update itself), and that the appcast's `sparkle:version` is higher than the installed `CFBundleVersion`.
- **"Signature invalid" in Sparkle.** The key in the app doesn't match the secret that signed the archive. Publish a new release with matching keys; copies installed from the mismatched build need a manual download once.
- **`duplicate output file` while building.** Don't pass both architectures to one `swift build`; `scripts/build-app.sh` builds each one separately and merges them with `lipo`.
- **Gatekeeper warning on first launch.** Releases are ad-hoc signed and not notarized. Installing with Homebrew or `npx` avoids it, since scripted downloads aren't quarantined. Notarization needs an Apple Developer ID; with one, add `codesign --options runtime` with the identity and `xcrun notarytool submit --wait` to `scripts/package-release.sh`.

## Trying the packaging locally

```bash
UNIVERSAL=1 DEVSWEEP_VERSION=0.0.0-test scripts/build-app.sh
DEVSWEEP_VERSION=0.0.0-test TAG=v0.0.0-test GITHUB_REPOSITORY=<owner>/DevSweep scripts/package-release.sh
```

Without `SPARKLE_PRIVATE_KEY` this produces the zip and its checksum and skips the appcast.
