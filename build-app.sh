#!/bin/bash
# Builds Lexicon and assembles a runnable, ad-hoc-signed .app bundle.
# Ad-hoc signing gives the binary a stable identity so macOS TCC remembers
# the Accessibility / Input Monitoring grants across launches.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Lexicon.app"
BIN_NAME="Lexicon"

echo "==> swift build (-c $CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: built binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> code signing"
SIGN_KC="$ROOT/.signing/lexicon-signing.keychain-db"
if [[ -f "$SIGN_KC" ]]; then
  # Stable self-signed identity → stable designated requirement → TCC grants
  # survive rebuilds. Run ./setup-signing.sh once to create it. The signing
  # keychain must be in the search list so codesign can evaluate its trust.
  CUR=$(security list-keychains -d user | tr -d '"' | sed 's/^ *//' | grep -v "lexicon-signing" | xargs)
  security list-keychains -d user -s "$SIGN_KC" $CUR
  security unlock-keychain -p "lexicon-signing" "$SIGN_KC" 2>/dev/null || true
  codesign --force --deep --sign "Lexicon Dev" --identifier com.lexicon.app "$APP"
else
  echo "   (no signing keychain — falling back to ad-hoc; run ./setup-signing.sh for stable grants)"
  codesign --force --deep --sign - "$APP"
fi

echo "==> done"
echo "Run:  open \"$APP\""
echo "  or: \"$APP/Contents/MacOS/$BIN_NAME\"   (foreground, for logs)"
