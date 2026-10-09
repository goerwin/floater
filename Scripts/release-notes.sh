#!/bin/bash
set -euo pipefail

TAG="${1:?Usage: Scripts/release-notes.sh <tag-or-revision>}"
if ! git rev-parse --verify --quiet "${TAG}^{commit}" >/dev/null; then
    echo "Ref '$TAG' does not resolve to a commit." >&2
    exit 1
fi

REPO_URL="${REPO_URL:-$(git config --get remote.origin.url || true)}"
REPO_URL="${REPO_URL%.git}"
REPO_URL="${REPO_URL/git@github.com:/https://github.com/}"
PREVIOUS_TAG="$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)"
RANGE="${PREVIOUS_TAG:+$PREVIOUS_TAG..}$TAG"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

emit() {
    if [[ -n "$REPO_URL" ]]; then
        printf -- '- %s ([%s](%s/commit/%s))\n' "$2" "$3" "$REPO_URL" "$3" >> "$TEMP_DIR/$1"
    else
        printf -- '- %s (%s)\n' "$2" "$3" >> "$TEMP_DIR/$1"
    fi
}

while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    [[ -z "$LINE" ]] && continue
    SUBJECT="${LINE%%$'\x1f'*}"
    HASH="${LINE##*$'\x1f'}"

    if [[ "$SUBJECT" =~ ^feat(\(.+\))?!?:[[:space:]]+(.+)$ ]]; then
        emit features "${BASH_REMATCH[2]}" "$HASH"
    elif [[ "$SUBJECT" =~ ^fix(\(.+\))?!?:[[:space:]]+(.+)$ ]]; then
        emit fixes "${BASH_REMATCH[2]}" "$HASH"
    else
        emit other "$SUBJECT" "$HASH"
    fi
done < <(git log --no-merges --pretty=format:'%s%x1f%h' "$RANGE")

for SECTION in "Features:features" "Fixes:fixes" "Other changes:other"; do
    FILE="$TEMP_DIR/${SECTION#*:}"
    [[ -s "$FILE" ]] || continue
    printf '### %s\n\n' "${SECTION%%:*}"
    cat "$FILE"
    printf '\n\n'
done
