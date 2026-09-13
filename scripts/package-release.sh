#!/usr/bin/env bash
# Packages build/DevSweep.app for a GitHub release (run by .github/workflows/release.yml).
# Produces in build/release/: the zip, its SHA-256, and appcast.xml for Sparkle.
#
# Required env: DEVSWEEP_VERSION, TAG, GITHUB_REPOSITORY.
# Optional env: SPARKLE_PRIVATE_KEY (EdDSA key from generate_keys -x). Without it the zip is
# still published, but the appcast is skipped and installed apps won't be offered the update.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${DEVSWEEP_VERSION:?set DEVSWEEP_VERSION}"
TAG="${TAG:?set TAG}"
REPOSITORY="${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY}"
OUT="build/release"
ZIP="DevSweep-$VERSION.zip"

rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent build/DevSweep.app "$OUT/$ZIP"
(cd "$OUT" && shasum -a 256 "$ZIP" > "$ZIP.sha256")
# Same archive under a stable name, so the Homebrew cask can point at
# releases/latest/download/DevSweep.zip and never need an update.
cp "$OUT/$ZIP" "$OUT/DevSweep.zip"
echo "✓ $OUT/$ZIP"

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "::warning::SPARKLE_PRIVATE_KEY is not set; skipping appcast. See .claude/skills/release/SKILL.md."
  exit 0
fi

SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
KEY_FILE="$(mktemp)"
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$OUT/$ZIP")"

# Release notes: the changelog that release-please wrote into the GitHub release.
NOTES="$(gh release view "$TAG" --repo "$REPOSITORY" --json body --jq .body 2>/dev/null || true)"
NOTES_HTML="$(printf '%s' "$NOTES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"

cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DevSweep</title>
    <link>https://github.com/$REPOSITORY/releases</link>
    <item>
      <title>DevSweep $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPOSITORY/releases</sparkle:fullReleaseNotesLink>
      <description><![CDATA[<pre style="white-space: pre-wrap; font: 13px -apple-system">$NOTES_HTML</pre>]]></description>
      <enclosure url="https://github.com/$REPOSITORY/releases/download/$TAG/$ZIP" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML
echo "✓ $OUT/appcast.xml"
