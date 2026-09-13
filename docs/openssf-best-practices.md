# OpenSSF Best Practices badge — prepared answers

Register the project at <https://www.bestpractices.dev/en/projects/new> (sign in with GitHub).
Most of the *passing* criteria are already met; this page is the evidence to paste in, so the
questionnaire takes minutes instead of an afternoon.

Replace `<owner>` with the repository owner. Criteria not listed here are either automatic or
answered "N/A" with the reason given below.

## Identification

| Field | Answer |
|---|---|
| Project name | DevSweep |
| Project homepage | `https://github.com/<owner>/DevSweep` |
| Repository | `https://github.com/<owner>/DevSweep` |
| Description | macOS menu bar app that finds developer processes stuck in limbo and cleans the caches, builds and simulator data that Flutter, iOS, Android, Node and Go leave behind. |
| Programming languages | Swift |
| CPE | leave empty |

## Basics

| Criterion | Answer | Evidence |
|---|---|---|
| Project website says what it does | Met | `README.md` |
| Website says how to get, give feedback, contribute | Met | `README.md` (Install, Contributing), `CONTRIBUTING.md` |
| Contribution requirements explained | Met | `CONTRIBUTING.md` documents the YAML schema, tests and commit conventions |
| Mentions DCO/CLA | N/A | No CLA; contributions are accepted under the project's MIT license |
| License is open source | Met | `LICENSE` (MIT), also declared in `packaging/npm/package.json` |
| License in standard location | Met | `LICENSE` at the repository root |
| Documentation: basic | Met | `README.md` |
| Documentation: interface | Met | `CONTRIBUTING.md` (stack/locale file schema, the project's public extension surface) |
| Documentation in English | Met | All repository docs are in English |

## Change control

| Criterion | Answer | Evidence |
|---|---|---|
| Public version-controlled source repository | Met | GitHub, git |
| Interim versions available | Met | Every commit on `main` |
| Unique version numbering | Met | SemVer, `version.txt` + git tags `vX.Y.Z` |
| Release notes for each release | Met | `CHANGELOG.md`, generated from Conventional Commits by release-please; also on each GitHub release |
| Release notes identify fixed vulnerabilities | Met (policy) | Security fixes are called out in the changelog and in the GitHub advisory |

## Reporting

| Criterion | Answer | Evidence |
|---|---|---|
| Bug reporting process | Met | GitHub Issues |
| Bug reports acknowledged | Met (policy) | — |
| Vulnerability report process | Met | `SECURITY.md` — GitHub private vulnerability reporting |
| Private vulnerability reporting | Met | Enabled on the repository; `SECURITY.md` links the advisory form |
| Response time to vulnerability reports | Met | `SECURITY.md` promises an initial reply within a week |

## Quality

| Criterion | Answer | Evidence |
|---|---|---|
| Working build system | Met | Swift Package Manager, `Makefile`, `scripts/build-app.sh` |
| Automated test suite | Met | `swift test` — 140+ tests, including validation of every stack and locale file |
| Tests are documented and easy to run | Met | `CONTRIBUTING.md`, `CLAUDE.md` |
| New functionality requires tests (policy) | Met | `CONTRIBUTING.md` and `CLAUDE.md` require a test with each new rule or provider |
| Tests run on every change | Met | `.github/workflows/ci.yml` runs on every push and pull request |
| Warning flags enabled / warnings fixed | Met | Builds are warning-free; SwiftLint-style conventions are enforced in review |
| Secure development knowledge | Met | Deletion is confined to the home folder (`SafeDelete`), process termination re-checks the PID's command, `PrivacyTests` keeps personal data out of the repository |

## Security

| Criterion | Answer | Evidence |
|---|---|---|
| Uses cryptography | Met | Update archives are signed with EdDSA (Sparkle); release assets are signed with Sigstore |
| Publicly documented crypto | Met | EdDSA (Ed25519), SHA-256 checksums, Sigstore/Fulcio certificates — `README.md`, `SECURITY.md` |
| No unencrypted network traffic | Met | The only network access is HTTPS to GitHub (update check and downloads) |
| Delivery against man-in-the-middle | Met | HTTPS, SHA-256 published with each release, EdDSA-signed updates, Sigstore signatures |
| Vulnerabilities fixed within 60 days | Met (policy) | `SECURITY.md` |
| No known unpatched vulnerabilities | Met | Dependabot, and the Scorecard "Vulnerabilities" check is at 10 |

## Analysis

| Criterion | Answer | Evidence |
|---|---|---|
| Static analysis on every change | Met | CodeQL (`security-extended` queries) on pushes and pull requests |
| Static analysis findings fixed | Met (policy) | Code scanning alerts are triaged before merging |
| Dynamic analysis | N/A / partial | No fuzzing: the Scorecard-recognized tools (OSS-Fuzz, ClusterFuzzLite) build in Linux containers, and this app uses macOS-only frameworks. Memory safety comes from Swift itself |
| Secret scanning | Met | TruffleHog on every push, plus GitHub secret scanning |

## Extra links worth pasting

- Test/CI status: `https://github.com/<owner>/DevSweep/actions/workflows/ci.yml`
- Coverage: `https://codecov.io/gh/<owner>/DevSweep`
- Scorecard: `https://scorecard.dev/viewer/?uri=github.com/<owner>/DevSweep`
- Security policy: `https://github.com/<owner>/DevSweep/security/policy`

Once the badge is granted, add its Markdown to the badge row in `README.md`. The OpenSSF
Scorecard "CII-Best-Practices" check picks it up on its next run.
