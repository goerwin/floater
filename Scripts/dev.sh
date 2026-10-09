#!/bin/bash
set -euo pipefail

FLOATER_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLOATER_APP_BUNDLE="$FLOATER_ROOT_DIR/build/Floater.app"

/usr/bin/killall -TERM Floater >/dev/null 2>&1 || true
"$FLOATER_ROOT_DIR/Scripts/build-app.sh" debug

if [[ -n "${FLOATER_PROMPT:-}" ]]; then
    FLOATER_LAUNCH_ARGS=(--prompt "$FLOATER_PROMPT")

    if [[ -n "${FLOATER_INPUT:-}" ]]; then
        FLOATER_LAUNCH_ARGS+=(--input "$FLOATER_INPUT")
    fi

    if [[ -n "${FLOATER_TITLE:-}" ]]; then
        FLOATER_LAUNCH_ARGS+=(--title "$FLOATER_TITLE")
    fi
else
    FLOATER_LAUNCH_ARGS=(--show-composer)
fi

/usr/bin/open -n "$FLOATER_APP_BUNDLE" --args "${FLOATER_LAUNCH_ARGS[@]}"
