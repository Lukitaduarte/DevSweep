# Maintaining DevSweep

Day-to-day releasing is automated: merge the pull request release-please keeps open and the
workflow publishes everything. This page is the setup behind that, done once per repository
and revisited when a token expires or an owner changes.

## Signing key for updates

```bash
scripts/setup-release-keys.sh <owner>/DevSweep
```

The script creates (or reuses) the Sparkle EdDSA key in your login keychain, writes the public
half to `Resources/sparkle-public-key.txt` — commit it — and stores the private half as the
`SPARKLE_PRIVATE_KEY` secret.

**Back the private key up** somewhere durable, for example a password manager:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
```

If that key is lost, every installed copy stops accepting updates and users have to download
the app again by hand. It's in the login keychain as *Private key for signing Sparkle updates*
(account `ed25519`, service `https://sparkle-project.org`).

## Repository settings

- Enable private vulnerability reporting, Dependabot alerts and secret scanning.
- Protect `main`: pull request required, and the `test`, `secret-scan`, `Analyze (swift)` and
  `Analyze (actions)` checks required.
- Settings → Actions → General → allow GitHub Actions to create pull requests. release-please
  can't open its release PR without it.

## Services

- **Codecov.** Sign in at codecov.io with GitHub, enable the repository, add the `CODECOV_TOKEN`
  secret. Pull requests from forks upload without it.
- **CodeRabbit.** Install the GitHub App (free for public repositories). The review instructions
  live in `.coderabbit.yaml`.
- **OpenSSF Scorecard.** Nothing to configure; the badge appears after the first run on `main`.

## Notarization

Releases are ad-hoc signed, not notarized, so macOS blocks the first launch of anything it
quarantined (Homebrew casks and manual downloads; `npx` installs are not quarantined). Removing
that for everyone needs a paid Apple Developer account: with one, add `codesign --options runtime`
using the Developer ID and `xcrun notarytool submit --wait` to `scripts/package-release.sh`, and
store the credentials as repository secrets.

## Homebrew

Nothing to set up. `Casks/devsweep.rb` lives in this repository and this repository is the tap:

```bash
brew trust --tap https://github.com/<owner>/DevSweep
brew tap <owner>/devsweep https://github.com/<owner>/DevSweep
brew install --cask devsweep
```

The trust command must name the URL: because this repository isn't called `homebrew-devsweep`,
the tap counts as having a custom remote, and `Tap#matches_reference?` only matches those by URL.
Trusting `<owner>/devsweep` is accepted silently and then never matches — which looks exactly
like the trust command not working.

Homebrew 7 refuses to load casks from an untrusted third-party tap, so the trust command is part
of the flow for everyone — it is not something the maintainer can configure away. Getting the
cask into the official `homebrew/cask` repository is what would remove it.

The two-argument form of `brew tap` is what allows a repository that isn't named
`homebrew-something`. The cask uses `version :latest` with `sha256 :no_check` against the stable
`releases/latest/download/DevSweep.zip` URL, and `auto_updates true` because the app updates
itself through Sparkle — so the file never needs to be touched again, and no release job
rewrites it.

If DevSweep ever becomes "notable" enough for the official `homebrew/cask` repository (roughly
75 stars or 30 forks), submitting it there would make plain `brew install --cask devsweep` work
with no tap at all.

## npm installer (optional)

The `npx @lukitaduarte/devsweep` installer is published with **trusted publishing**: npm trusts this
repository's release workflow directly through OIDC, so no token is ever stored. npm warns
against automation tokens for CI for good reason — a leaked one can publish anything, forever.

Trusted publishing can only be attached to a package that already exists, so the first version
goes up by hand, from a terminal, with no token at all:

```bash
npm login                               # asks for your 2FA code
cd packaging/npm
npm version <version> --no-git-tag-version
npm publish --access public             # asks for the 2FA code again
```

The package is scoped (`@<user>/devsweep`) on purpose: npm rejects unscoped names that are
*similar* to an existing package, not only names already taken, and `devsweep` collides with
`dev-sweep`. A scope belongs to you, so it can't be refused.

Then, on <https://www.npmjs.com/package/@<user>/devsweep/access>, add a trusted publisher:

| Field | Value |
|---|---|
| Publisher | GitHub Actions |
| Organization / user | `<owner>` |
| Repository | `DevSweep` |
| Workflow filename | `release.yml` |
| Environment | leave empty |

Finally, let the workflow publish from now on:

```bash
gh variable set PUBLISH_NPM --repo <owner>/DevSweep --body true
```

If you created an automation token to get here, delete it at
<https://www.npmjs.com/settings/~/tokens>; it isn't needed any more.

Releases run npm 11 on Node 22 (the versions that speak OIDC) and publish with
`id-token: write`, which also attaches provenance automatically. Without the `PUBLISH_NPM`
variable the job is skipped and everything else in the release still runs.


## Secrets and variables at a glance

| Name | Kind | Used by | Missing means |
|---|---|---|---|
| `SPARKLE_PRIVATE_KEY` | secret | signing the update archive | release publishes without `appcast.xml`, installed apps see no update |
| `CODECOV_TOKEN` | secret | coverage upload | coverage isn't reported for pushes |
| `PUBLISH_NPM` | variable | the npm publish job | `npx @lukitaduarte/devsweep` keeps installing the previous version |

Only two secrets exist, and neither can publish anything on its own: npm goes through trusted
publishing and Homebrew reads a plain URL.
