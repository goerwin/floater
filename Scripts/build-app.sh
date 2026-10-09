#!/bin/bash
set -euo pipefail

FLOATER_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLOATER_BUILD_CONFIGURATION="${1:-release}"
FLOATER_APP_BUNDLE="$FLOATER_ROOT_DIR/build/Floater.app"
FLOATER_VERSION="${FLOATER_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FLOATER_ROOT_DIR/Resources/Info.plist")}"
FLOATER_MODULE_CACHE="$FLOATER_ROOT_DIR/.build/module-cache"
FLOATER_SPM_CACHE="$FLOATER_ROOT_DIR/.build/spm-cache"
FLOATER_SPM_CONFIG="$FLOATER_ROOT_DIR/.build/spm-config"
FLOATER_SPM_SECURITY="$FLOATER_ROOT_DIR/.build/spm-security"

if [[ ! "$FLOATER_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "FLOATER_VERSION must be a stable MAJOR.MINOR.PATCH version." >&2
    exit 2
fi

mkdir -p "$FLOATER_MODULE_CACHE" "$FLOATER_SPM_CACHE" "$FLOATER_SPM_CONFIG" "$FLOATER_SPM_SECURITY"
FLOATER_BUILD_BIN_DIR="$(env SWIFTPM_MODULECACHE_OVERRIDE="$FLOATER_MODULE_CACHE" swift build \
    --package-path "$FLOATER_ROOT_DIR" \
    --cache-path "$FLOATER_SPM_CACHE" \
    --config-path "$FLOATER_SPM_CONFIG" \
    --security-path "$FLOATER_SPM_SECURITY" \
    --manifest-cache local \
    --disable-sandbox \
    --configuration "$FLOATER_BUILD_CONFIGURATION" \
    --show-bin-path)"

env SWIFTPM_MODULECACHE_OVERRIDE="$FLOATER_MODULE_CACHE" swift build \
    --package-path "$FLOATER_ROOT_DIR" \
    --cache-path "$FLOATER_SPM_CACHE" \
    --config-path "$FLOATER_SPM_CONFIG" \
    --security-path "$FLOATER_SPM_SECURITY" \
    --manifest-cache local \
    --disable-sandbox \
    --configuration "$FLOATER_BUILD_CONFIGURATION"

rm -rf "$FLOATER_APP_BUNDLE"
mkdir -p "$FLOATER_APP_BUNDLE/Contents/MacOS"
cp "$FLOATER_BUILD_BIN_DIR/Floater" "$FLOATER_APP_BUNDLE/Contents/MacOS/Floater"
cp "$FLOATER_BUILD_BIN_DIR/FloaterCLI" "$FLOATER_APP_BUNDLE/Contents/MacOS/floater-cli"
cp "$FLOATER_ROOT_DIR/Resources/Info.plist" "$FLOATER_APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $FLOATER_VERSION" "$FLOATER_APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $FLOATER_VERSION" "$FLOATER_APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$FLOATER_APP_BUNDLE/Contents/PkgInfo"

if [[ -n "${CODE_SIGNING_IDENTITY:-}" ]]; then
    /usr/bin/codesign --force --options runtime --timestamp --sign "$CODE_SIGNING_IDENTITY" "$FLOATER_APP_BUNDLE/Contents/MacOS/floater-cli"
    /usr/bin/codesign --force --options runtime --timestamp --sign "$CODE_SIGNING_IDENTITY" "$FLOATER_APP_BUNDLE"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$FLOATER_APP_BUNDLE"
fi

printf 'Built %s\n' "$FLOATER_APP_BUNDLE"
