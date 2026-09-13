#!/usr/bin/env bash
# Builds DevSweep.app into ./build.
#   --install                copy it to /Applications and launch it
#   UNIVERSAL=1              build for Apple silicon and Intel (the release workflow does this)
#   DEVSWEEP_VERSION=x.y.z   override the version from version.txt
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/DevSweep.app"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"
VERSION="${DEVSWEEP_VERSION:-$(tr -d '[:space:]' < version.txt)}"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  # Asking for both architectures in one invocation switches SwiftPM to the Xcode build
  # system, which fails with "duplicate output file" on some toolchains. Build each
  # architecture on its own and merge the executables with lipo.
  swift build -c release --arch arm64 --scratch-path .build/uni-arm64
  swift build -c release --arch x86_64 --scratch-path .build/uni-x86_64
  BIN_DIR="$(swift build -c release --arch arm64 --scratch-path .build/uni-arm64 --show-bin-path)"
  X86_BIN_DIR="$(swift build -c release --arch x86_64 --scratch-path .build/uni-x86_64 --show-bin-path)"
  mkdir -p build/universal
  BIN="build/universal/DevSweep"
  lipo -create -output "$BIN" "$BIN_DIR/DevSweep" "$X86_BIN_DIR/DevSweep"
else
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
  BIN="$BIN_DIR/DevSweep"
fi

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Frameworks" "$RESOURCES/stacks" "$RESOURCES/locales"
cp "$BIN" "$CONTENTS/MacOS/DevSweep"
cp -R "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/DevSweep" 2>/dev/null || true

cp Resources/Info.plist "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$CONTENTS/Info.plist"
# The public half of the Sparkle signing key. Builds without it can't self-update.
if [[ -f Resources/sparkle-public-key.txt ]]; then
  plutil -replace SUPublicEDKey -string "$(tr -d '[:space:]' < Resources/sparkle-public-key.txt)" "$CONTENTS/Info.plist"
fi

cp -R Resources/*.lproj "$RESOURCES/"
cp stacks/*.yaml "$RESOURCES/stacks/"
cp locales/*.yaml "$RESOURCES/locales/"

if [[ ! -f build/AppIcon.icns ]]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$RESOURCES/AppIcon.icns"

# Debug symbols embed absolute build paths (home folder, username). Strip them, then refuse to
# produce a bundle that still contains any.
strip -S -x "$CONTENTS/MacOS/DevSweep"
HOMES_ROOT="$(dirname "$HOME")/"
if grep -rqaF -e "$HOMES_ROOT" -e "$HOME" "$APP"; then
  echo "error: the app bundle contains an absolute home path:" >&2
  grep -rlaF -e "$HOMES_ROOT" -e "$HOME" "$APP" >&2
  exit 1
fi

# Ad-hoc signature, including the embedded Sparkle framework and its helpers.
codesign --force --deep --sign - "$APP"
echo "✓ $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x DevSweep 2>/dev/null || true
  rm -rf /Applications/DevSweep.app
  cp -R "$APP" /Applications/
  open /Applications/DevSweep.app
  echo "✓ Installed in /Applications and launched"
fi
