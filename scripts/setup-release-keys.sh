#!/usr/bin/env bash
# One-time setup for signed auto-updates (maintainers only).
#
# 1. Creates the Sparkle EdDSA key pair in your login keychain (or reuses the existing one).
# 2. Writes the public key to Resources/sparkle-public-key.txt. Commit that file.
# 3. Stores the private key as the SPARKLE_PRIVATE_KEY secret of the GitHub repository (needs `gh auth login`).
#
# Usage: scripts/setup-release-keys.sh [owner/repo]
set -euo pipefail
cd "$(dirname "$0")/.."

REPOSITORY="${1:-$(plutil -extract DevSweepRepository raw Resources/Info.plist)}"
swift package resolve >/dev/null
BIN=".build/artifacts/sparkle/Sparkle/bin"

"$BIN/generate_keys" >/dev/null
"$BIN/generate_keys" -p > Resources/sparkle-public-key.txt
echo "✓ Public key written to Resources/sparkle-public-key.txt (commit it)"

KEY_FILE="$(mktemp)"
trap 'rm -f "$KEY_FILE"' EXIT
rm -f "$KEY_FILE" # generate_keys -x refuses to overwrite an existing file
"$BIN/generate_keys" -x "$KEY_FILE"
gh secret set SPARKLE_PRIVATE_KEY --repo "$REPOSITORY" < "$KEY_FILE"
echo "✓ Private key stored as SPARKLE_PRIVATE_KEY in $REPOSITORY"
echo "  It stays in your keychain too. Back it up: without it, installed copies can't receive updates."
