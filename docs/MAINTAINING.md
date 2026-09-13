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

## Homebrew tap (optional)

Homebrew installs from a "tap", which is a public repository whose name starts with `homebrew-`.

```bash
gh repo create <owner>/homebrew-tap --public \
  --description "Homebrew tap for DevSweep" --add-readme
```

Create a **fine-grained** token at <https://github.com/settings/personal-access-tokens/new>:
resource owner `<owner>`, *Only select repositories* → `homebrew-tap`, permission
*Contents: Read and write*, nothing else. Then:

```bash
gh secret set HOMEBREW_TAP_TOKEN --repo <owner>/DevSweep
```

The workflow's own token can't be used, because it only reaches the repository it runs in.
From the next release on, `Casks/devsweep.rb` is written into the tap and
`brew install --cask <owner>/tap/devsweep` works.

## npm installer (optional)

Publishing the `npx devsweep` installer needs an npm account with 2FA and an **automation**
token — the only kind that works in CI with 2FA enabled. Create one at
<https://www.npmjs.com/settings/~/tokens> (*Generate New Token* → *Classic* → *Automation*):

```bash
gh secret set NPM_TOKEN --repo <owner>/DevSweep
```

Check the name is free with `npm view devsweep` (a 404 means free). If it's taken, rename the
package in `packaging/npm/package.json` to `@<user>/devsweep`; people then run
`npx @<user>/devsweep`.

## When a token expires

Fine-grained GitHub tokens last at most a year and npm tokens can expire too. The release keeps
working when they do — the Homebrew and npm jobs log a notice and skip — so watch for that notice
in the release run, create a new token the same way and overwrite the secret with `gh secret set`.

## Secrets at a glance

| Secret | Used by | Missing means |
|---|---|---|
| `SPARKLE_PRIVATE_KEY` | signing the update archive | release publishes without `appcast.xml`, installed apps see no update |
| `CODECOV_TOKEN` | coverage upload | coverage isn't reported for pushes |
| `HOMEBREW_TAP_TOKEN` | updating the cask in the tap | `brew upgrade` keeps the previous version |
| `NPM_TOKEN` | publishing the npx installer | `npx devsweep` keeps installing the previous version |
