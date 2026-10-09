#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: Scripts/release.sh <patch|minor|major> [--preview]" >&2
}

PREVIEW=0
if [[ $# -eq 2 && ( "$2" == "--preview" || "$2" == "-n" ) ]]; then
    PREVIEW=1
    set -- "$1"
fi

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

BUMP="$1"
case "$BUMP" in
    patch) RELEASE_TYPE="Patch" ;;
    minor) RELEASE_TYPE="Minor" ;;
    major) RELEASE_TYPE="Major" ;;
    *)
        usage
        exit 2
        ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Run this script from inside the Git repository." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    echo "Working tree is not clean. Commit or stash your changes first." >&2
    exit 1
fi

REMOTE="${RELEASE_REMOTE:-origin}"
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "Git remote '$REMOTE' is not configured." >&2
    exit 1
fi
git fetch --tags "$REMOTE"

LATEST_TAG=""
while IFS= read -r TAG; do
    if [[ "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        LATEST_TAG="$TAG"
        break
    fi
done < <(git tag --list 'v[0-9]*' --sort=-version:refname)

if [[ -n "$LATEST_TAG" ]]; then
    if ! git merge-base --is-ancestor "$LATEST_TAG" HEAD; then
        echo "Latest release tag '$LATEST_TAG' is not in the current commit history." >&2
        exit 1
    fi
    BASE_VERSION="${LATEST_TAG#v}"
else
    BASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
    if [[ ! "$BASE_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        echo "No stable release tag exists, and Info.plist has an invalid starting version." >&2
        exit 1
    fi
fi

IFS=. read -r MAJOR MINOR PATCH <<< "$BASE_VERSION"
MAJOR=$((10#$MAJOR))
MINOR=$((10#$MINOR))
PATCH=$((10#$PATCH))

case "$BUMP" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
esac

NEW_TAG="v$MAJOR.$MINOR.$PATCH"
if git show-ref --verify --quiet "refs/tags/$NEW_TAG"; then
    echo "Tag '$NEW_TAG' already exists locally." >&2
    exit 1
fi

printf '\n%s release: %s -> %s\n\n' "$RELEASE_TYPE" "${LATEST_TAG:-v$BASE_VERSION (Info.plist)}" "$NEW_TAG"
printf 'Release notes preview:\n\n'
Scripts/release-notes.sh HEAD
printf '\n'

if [[ "$PREVIEW" -eq 1 ]]; then
    echo "Preview only. No tag was created or pushed."
    exit 0
fi

printf 'Push %s to %s and start the GitHub release workflow? [y/N] ' "$NEW_TAG" "$REMOTE"
IFS= read -r ANSWER || ANSWER=""
case "$ANSWER" in
    y|Y|yes|YES|Yes) ;;
    *)
        echo "Cancelled. No tag was created or pushed."
        exit 0
        ;;
esac

git tag "$NEW_TAG"
if ! git push "$REMOTE" "refs/tags/$NEW_TAG:refs/tags/$NEW_TAG"; then
    git tag -d "$NEW_TAG" >/dev/null 2>&1 || true
    echo "Push failed. Removed local tag '$NEW_TAG'; retry after fixing the issue." >&2
    exit 1
fi

echo "Pushed $NEW_TAG. GitHub Actions will build and publish the release."
