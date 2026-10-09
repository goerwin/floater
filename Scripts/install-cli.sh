#!/bin/bash
set -euo pipefail

FLOATER_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLOATER_SOURCE_APP="$FLOATER_ROOT_DIR/build/Floater.app"
FLOATER_APPLICATIONS_DIR="$HOME/Applications"
FLOATER_APP_BUNDLE="$FLOATER_APPLICATIONS_DIR/Floater.app"
FLOATER_BIN_DIR="$HOME/.local/bin"

if [[ ! -x "$FLOATER_SOURCE_APP/Contents/MacOS/Floater" ]]; then
    "$FLOATER_ROOT_DIR/Scripts/build-app.sh"
fi

mkdir -p "$FLOATER_APPLICATIONS_DIR" "$FLOATER_BIN_DIR"
rm -rf "$FLOATER_APP_BUNDLE"
ditto "$FLOATER_SOURCE_APP" "$FLOATER_APP_BUNDLE"
ln -sfn "$FLOATER_APP_BUNDLE/Contents/MacOS/floater-cli" "$FLOATER_BIN_DIR/floater"
open "$FLOATER_APP_BUNDLE"

printf 'Installed Floater.app to %s\n' "$FLOATER_APP_BUNDLE"
printf 'CLI command: %s/floater\n' "$FLOATER_BIN_DIR"
