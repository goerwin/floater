#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
    echo "Usage: Scripts/make-dmg.sh <Floater.app>" >&2
    exit 2
fi

APP_SOURCE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
APP_NAME="$(basename "$APP_SOURCE")"
BUNDLE_NAME="${APP_NAME%.app}"
DIST_DIR="${DIST_DIR:-dist}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_SOURCE/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/$BUNDLE_NAME-$VERSION.dmg"

mkdir -p "$DIST_DIR"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/floater-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP_SOURCE" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$BUNDLE_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null

printf '%s\n' "$DMG_PATH"
