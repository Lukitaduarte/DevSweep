# OpenSSF Best Practices badge

**Status: passing** — <https://www.bestpractices.dev/projects/14624>

This page records what was answered in the badge questionnaire and the evidence behind each
answer, so the entry can be kept honest as the project changes. Anyone with commit access to
this repository can edit the entry, so please update both together.

Criteria that the site fills in automatically (repository, license file, release notes) are not
repeated here. What follows is everything that needed a human answer.

## The honest gaps

Three criteria are answered *Unmet* on purpose. None of them blocks the passing level, because
they are SHOULD or SUGGESTED criteria.

| Criterion | Why | Could change? |
|---|---|---|
| `build_floss_tools` | A native macOS app needs Apple's proprietary SDK (AppKit, SwiftUI) to build, and packaging uses Apple tools shipped with macOS | No |
| `warnings_strict` | Warnings are not treated as errors and no linter is configured; the build simply happens to be warning-free | Yes, cheaply |
| `dynamic_analysis` | The test suite runs on every change, but no fuzzer or sanitizer is part of the pipeline | Yes, with a sanitizer job |

## Identification

| Field | Value |
|---|---|
| Project name | DevSweep |
| Homepage and repository | `https://github.com/Lukitaduarte/DevSweep` |
| Programming language | Swift |

## Maintenance and reporting

| Criterion | Answer | Evidence |
|---|---|---|
| `maintained` | Met | Under active development with regular releases; issues and pull requests are triaged by the maintainer |
| `report_responses` | Met | No external bug reports yet; GitHub Issues is enabled and monitored |
| `enhancement_responses` | Met | No enhancement requests yet; they go to GitHub Issues and get an answer, even when it's no |
| `report_archive` | Met | `https://github.com/Lukitaduarte/DevSweep/issues` — public and searchable |
| `vulnerability_report_process` | Met | `SECURITY.md`: don't open a public issue, use the private channel |
| `vulnerability_report_private` | Met | GitHub private vulnerability reporting is enabled: `/security/advisories/new` |
| `vulnerability_report_response` | N/A | No vulnerability reports received. `SECURITY.md` promises a first reply within a week, inside the 14-day requirement |

## Documentation and contribution

| Criterion | Answer | Evidence |
|---|---|---|
| Basic and interface documentation | Met | `README.md`, and `CONTRIBUTING.md` for the stack and locale schema, which is the extension surface |
| `contribution_requirements` | Met | `CONTRIBUTING.md`: schema, commands that must pass, Conventional Commits, how risk levels are classified, the rule that `run:` may only call the stack's own CLI, and the ban on personal paths |

## Build and tests

| Criterion | Answer | Evidence |
|---|---|---|
| `build_floss_tools` | **Unmet** | Swift, SwiftPM, Yams and Sparkle are all FLOSS, but building needs Apple's macOS SDK and packaging uses `codesign`, `ditto`, `lipo`, `plutil` and `iconutil` |
| `test` | Met | `swift test` — 142 tests, including validation of every stack and locale file |
| `test_invocation` | Met | `swift test`, the standard SwiftPM command |
| `test_most` | Met | 91% of regions, enforced at 90% by Codecov; SwiftUI views and system glue (`AppModel`, `Updater`, `Notifier`) are excluded in `codecov.yml` because they need a UI host |
| `test_continuous_integration` | Met | `.github/workflows/ci.yml` on every push and pull request |
| `test_policy` | Met | `CLAUDE.md` and `CONTRIBUTING.md` require a test with each new provider, and a grouping test for each new or broader process rule |
| `tests_are_added` | Met | The coverage work added 142 tests; stack and locale contributions are validated automatically |
| `tests_documented_added` | Met | `CONTRIBUTING.md` ("Verify") and the pull request template |

## Warnings and analysis

| Criterion | Answer | Evidence |
|---|---|---|
| `warnings` | Met | Swift compiles with warnings on by default and is a memory-safe language mode; CodeQL adds `security-extended` |
| `warnings_fixed` | Met | `swift build` reports no warnings in the project's own sources |
| `warnings_strict` | **Unmet** | No `-warnings-as-errors`, no SwiftLint or swift-format |
| `static_analysis` | Met | CodeQL on every push, every pull request and weekly |
| `static_analysis_common_vulnerabilities` | Met | `security-extended` query suite |
| `static_analysis_fixed` | Met | Alerts are triaged before merging; none raised so far |
| `static_analysis_often` | Met | Every push and pull request |
| `dynamic_analysis` | **Unmet** | Tests run on every change with Swift's runtime checks active, but there is no fuzzer, sanitizer or scanner |
| `dynamic_analysis_unsafe` | N/A | The software produced is entirely Swift; the only C in the tree is libyaml, vendored by Yams |
| `dynamic_analysis_enable_assertions` | Met | Tests run in debug, where preconditions, bounds checks and overflow traps are active |
| `dynamic_analysis_fixed` | Met | Nothing found |

## Security

| Criterion | Answer | Evidence |
|---|---|---|
| `know_secure_design` | Met | Least privilege (never root, only the user's own processes), fail-safe defaults (destructive items never run in bulk), validated input (schema-checked YAML), confinement (`SafeDelete`) |
| `know_common_errors` | Met | Path traversal, TOCTOU and PID reuse, command injection (commands run as argument vectors, never through a shell), supply-chain risk, credential leakage — each with the mitigation in place |
| `delivery_mitm` | Met | HTTPS everywhere |
| `delivery_unsigned` | Met | Updates carry an EdDSA signature verified before install; the installer checks the SHA-256 published with the release; assets also carry Sigstore signatures |
| `vulnerabilities_fixed_60_days` | Met | None known; Dependabot and CodeQL watch for them |
| `vulnerabilities_critical_fixed` | Met | `SECURITY.md`: first reply within a week, fix within 60 days |
| `no_leaked_credentials` | Met | TruffleHog and GitHub secret scanning on every push, plus a test that fails on personal paths or emails. The only key material committed is the *public* half of the Sparkle key |

## Cryptography

The app verifies Ed25519 signatures (through Sparkle) and SHA-256 checksums, so the "does not
use cryptographic mechanisms" shortcut does not apply. It implements none of it itself.

| Criterion | Answer | Evidence |
|---|---|---|
| `crypto_published` | Met | Ed25519, SHA-256, TLS |
| `crypto_call` | Met | Signature verification via Sparkle, TLS via the OS, SHA-256 via Node's `crypto` in the installer |
| `crypto_floss` | Met | Sparkle is MIT; the primitives are all implementable with FLOSS |
| `crypto_keylength` | Met | Ed25519 (≈128-bit) and SHA-256 exceed the NIST minimums through 2030; no weaker option exists to disable |
| `crypto_working` | Met | No MD4, MD5, SHA-1, DES, RC4 or Dual_EC_DRBG |
| `crypto_weaknesses` | Met | Same |
| `crypto_pfs` | N/A | No key agreement protocol is implemented; TLS comes from the OS |
| `crypto_password_storage` | N/A | No user passwords or credentials are stored |
| `crypto_random` | N/A | No keys or nonces are generated at runtime; the signing key is generated offline by Sparkle's `generate_keys` |

## Keeping this honest

If the pipeline gains a sanitizer job or `-warnings-as-errors`, update `dynamic_analysis` and
`warnings_strict` in the badge entry and in the table above. If a vulnerability is ever reported,
`vulnerability_report_response` moves from N/A to Met or Unmet depending on the response time.
