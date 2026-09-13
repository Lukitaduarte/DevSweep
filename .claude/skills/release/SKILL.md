---
name: release
description: Cut a DevSweep release or fix the release pipeline, including the one-time maintainer setup of Sparkle signing keys, repository secrets, Codecov and CodeRabbit. Use when asked to publish a version, when the release PR, appcast or auto-update misbehaves, or when setting up the repository on GitHub.
---

# Release DevSweep

## How it works

1. Commits on `main` follow Conventional Commits (`feat:`, `fix:`, `perf:`, `deps:`; `feat!:` or a `BREAKING CHANGE:` footer for majors).
2. `.github/workflows/release.yml` runs release-please on every push to `main`. It keeps a "chore(main): release x.y.z" PR updated with the bumped `version.txt`, `.release-please-manifest.json` and `CHANGELOG.md`.
3. **Merging that PR** creates the `vX.Y.Z` tag and the GitHub release with the changelog. The `build` job then:
   - runs the tests;
   - builds a universal app with `UNIVERSAL=1 scripts/build-app.sh`, with the version injected from release-please;
   - runs `scripts/package-release.sh` to zip the app, write its SHA-256, sign the zip with Sparkle's `sign_update` and write `appcast.xml` with the release notes;
   - generates an SPDX SBOM and signs the zip and the SBOM with Sigstore (keyless, using the workflow's OIDC identity, so there is no key to leak);
   - uploads everything to the release.

To rebuild the assets of a tag that already exists (a release whose build failed, for example), run the workflow by hand: `gh workflow run release.yml -f tag=v0.1.0`. It checks out that tag, rebuilds and re-uploads with `--clobber`.
4. Installed apps read `https://github.com/<repo>/releases/latest/download/appcast.xml` once a day (`SUFeedURL` in `Resources/Info.plist`). They show an "update available" card with a Changelog link, and install with one click after Sparkle verifies the EdDSA signature.

To release: review and merge the release PR. Nothing else is manual.

## One-time setup (maintainer)

1. **Sparkle keys.** Run `scripts/setup-release-keys.sh` (or pass `owner/repo`). It:
   - creates or reuses the EdDSA key in the login keychain;
   - writes `Resources/sparkle-public-key.txt`, which must be committed (it's public);
   - sets the `SPARKLE_PRIVATE_KEY` secret with `gh`.

   Back up the private key (`generate_keys -x`). If it's lost, existing installs can never verify an update again.
2. **Codecov.** Sign in at codecov.io with GitHub, enable the repo and add the `CODECOV_TOKEN` secret. Uploads from forks work without it.
3. **CodeRabbit.** Install the CodeRabbit GitHub App on the repository (free for public repos). `.coderabbit.yaml` holds the review instructions.
4. **Repository settings.**
   - Enable private vulnerability reporting, Dependabot alerts and secret scanning.
   - Protect `main`: require the CI, CodeQL and secret-scan checks.
   - Allow GitHub Actions to create pull requests (Settings → Actions → General), which release-please needs.
5. **Scorecard.** Its badge appears after the first run on `main`.
6. **Homebrew (optional).** Create a public repository named `homebrew-tap` under the same owner, then add a `HOMEBREW_TAP_TOKEN` secret: a fine-grained personal access token with *Contents: read and write* on that repository only. Each release rewrites `Casks/devsweep.rb` there from `packaging/homebrew/devsweep.rb`, so `brew install --cask <owner>/tap/devsweep` gets the new version.
7. **npm (optional).** Create an npm automation token and add it as `NPM_TOKEN`. Each release publishes `packaging/npm` (the `npx devsweep` installer) with provenance. Without the secret the job logs a notice and is skipped.

## Troubleshooting

- **No release PR:** there are no `feat`/`fix`/`perf`/`deps` commits since the last release, or Actions can't create PRs (step 4).
- **Release published without `appcast.xml`:** `SPARKLE_PRIVATE_KEY` is missing (the job logs a warning). Fix the secret, then rerun the `build` job.
- **Installed app never offers updates:** the build had no public key, so `Updater.isEnabled` is false and Settings says the build can't update itself. Check that `Resources/sparkle-public-key.txt` was committed before the release. Also check that the appcast `sparkle:version` is higher than the installed `CFBundleVersion`.
- **"Signature invalid" in Sparkle:** the public key in the app doesn't match the secret. Re-run the setup script and publish a new release; old installs need a manual download once.
- **Gatekeeper warning on first install:** releases are ad-hoc signed and not notarized. The README tells users to right-click → Open once. Notarization needs an Apple Developer ID; if one becomes available, add `codesign --options runtime` with the identity and `xcrun notarytool submit --wait` to `package-release.sh`, with credentials as secrets.

## Testing the packaging locally

```bash
UNIVERSAL=1 DEVSWEEP_VERSION=0.0.0-test scripts/build-app.sh
DEVSWEEP_VERSION=0.0.0-test TAG=v0.0.0-test GITHUB_REPOSITORY=owner/repo scripts/package-release.sh   # without SPARKLE_PRIVATE_KEY: zip + sha only
```
