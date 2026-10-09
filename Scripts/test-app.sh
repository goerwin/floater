#!/bin/bash
set -euo pipefail

FLOATER_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLOATER_SMOKE_BINARY="$FLOATER_ROOT_DIR/.build/smoke-test/test-app"

case "${1:-}" in
    "") FLOATER_SMOKE_BUILD=true ;;
    --no-build) FLOATER_SMOKE_BUILD=false ;;
    --help)
        printf 'Usage: Scripts/test-app.sh [--no-build]\nRequires Accessibility access for the terminal or app running this script.\n'
        exit 0
        ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

mkdir -p "$(dirname "$FLOATER_SMOKE_BINARY")" "$FLOATER_ROOT_DIR/.build/module-cache"
xcrun swiftc -module-cache-path "$FLOATER_ROOT_DIR/.build/module-cache" \
    -parse-as-library "$FLOATER_ROOT_DIR/Scripts/SmokeTest.swift" -o "$FLOATER_SMOKE_BINARY"
"$FLOATER_SMOKE_BINARY" --check-access

/usr/bin/killall -TERM Floater >/dev/null 2>&1 || true
if $FLOATER_SMOKE_BUILD; then
    "$FLOATER_ROOT_DIR/Scripts/build-app.sh" debug
fi

FLOATER_SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/floater-smoke.XXXXXX")"
trap '/usr/bin/killall -TERM Floater >/dev/null 2>&1 || true; rm -rf "$FLOATER_SMOKE_DIR"' EXIT
"$FLOATER_SMOKE_BINARY" "$FLOATER_ROOT_DIR/build/Floater.app" "$FLOATER_SMOKE_DIR"
