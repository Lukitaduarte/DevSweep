# Security Policy

DevSweep deletes files and stops processes on your Mac, so we take its safety seriously.

## Supported versions

Only the [latest release](https://github.com/Lukitaduarte/DevSweep/releases/latest) receives fixes. The app updates itself, so staying current is one click.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately through [GitHub's vulnerability reporting](https://github.com/Lukitaduarte/DevSweep/security/advisories/new). You'll get an initial reply within a week, and we'll credit you in the release notes unless you prefer otherwise.

These are especially relevant:

- A way to make DevSweep delete files outside the paths declared in `stacks/`, or outside your home folder.
- A way to make it stop a process that doesn't belong to the current user or doesn't match a rule.
- Anything that lets a stack file or a pull request run arbitrary commands without it being obvious in review.
- Weaknesses in the update process (appcast, signatures, downloads).

## How DevSweep protects you

- Deletion goes through `SafeDelete`, which only accepts paths inside your home folder and refuses well-known roots such as `~/Documents` and `~/Library/Caches`.
- Before stopping a process, it checks that the PID still runs the same command line.
- It never runs as root and only sees processes owned by your user.
- Its only network access is the daily update check against this repository's GitHub releases. Updates are verified with an EdDSA signature (Sparkle) before they're installed.
- Every change runs through CodeQL, secret scanning, the OpenSSF Scorecard and automated tests, including a test that fails if personal data lands in the repository.
