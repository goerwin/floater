#!/bin/bash
set -euo pipefail

FLOATER_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLOATER_BUILD_CONFIGURATION="${1:-release}"
FLOATER_APP_BUNDLE="$FLOATER_ROOT_DIR/build/Floater.app"
if [[ "$FLOATER_BUILD_CONFIGURATION" == debug ]]; then
    FLOATER_VERSION=0.0.0
else
    FLOATER_VERSION="${FLOATER_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FLOATER_ROOT_DIR/Resources/Info.plist")}"
fi
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
mkdir -p "$FLOATER_APP_BUNDLE/Contents/Resources"
mkdir -p "$FLOATER_APP_BUNDLE/Contents/Frameworks"
FLOATER_SPARKLE_FRAMEWORK="$FLOATER_ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$FLOATER_SPARKLE_FRAMEWORK" "$FLOATER_APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
cp "$FLOATER_BUILD_BIN_DIR/Floater" "$FLOATER_APP_BUNDLE/Contents/MacOS/Floater"
while IFS= read -r rpath; do
    if [[ "$rpath" == /* ]]; then
        /usr/bin/install_name_tool -delete_rpath "$rpath" "$FLOATER_APP_BUNDLE/Contents/MacOS/Floater"
    fi
done < <(/usr/bin/otool -l "$FLOATER_APP_BUNDLE/Contents/MacOS/Floater" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }')
cp "$FLOATER_BUILD_BIN_DIR/FloaterCLI" "$FLOATER_APP_BUNDLE/Contents/MacOS/floater-cli"
cp "$FLOATER_ROOT_DIR/Resources/Info.plist" "$FLOATER_APP_BUNDLE/Contents/Info.plist"
cp "$FLOATER_ROOT_DIR/Resources/Generated/Floater.icns" "$FLOATER_APP_BUNDLE/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $FLOATER_VERSION" "$FLOATER_APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $FLOATER_VERSION" "$FLOATER_APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$FLOATER_APP_BUNDLE/Contents/PkgInfo"

find_development_identities() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Apple Development' \
        | grep -v 'CSSMERR_TP_CERT_REVOKED' \
        | awk '{print $2}' || true
}

verify_signing_certificate() {
    local certificate_dir result=0
    certificate_dir="$(mktemp -d "${TMPDIR:-/tmp}/floater-signing.XXXXXX")" || return
    (
        cd "$certificate_dir" || exit
        /usr/bin/codesign --display --extract-certificates "$FLOATER_APP_BUNDLE" >/dev/null 2>&1
    ) && [[ -f "$certificate_dir/codesign0" ]] \
        && /usr/bin/security verify-cert -p codeSign -R ocsp -q -c "$certificate_dir/codesign0" || result=$?
    rm -rf "$certificate_dir"
    if [[ "$result" -ne 0 ]]; then
        printf 'Signing certificate is unavailable or not trusted.\n' >&2
    fi
    return "$result"
}

if [[ "$FLOATER_BUILD_CONFIGURATION" != debug && -n "${CODE_SIGNING_IDENTITY:-}" ]]; then
    FLOATER_EMBEDDED_SPARKLE="$FLOATER_APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
    for component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Updater.app Autoupdate; do
        /usr/bin/codesign --force --options runtime --timestamp --sign "$CODE_SIGNING_IDENTITY" "$FLOATER_EMBEDDED_SPARKLE/$component"
    done
    /usr/bin/codesign --force --options runtime --timestamp --sign "$CODE_SIGNING_IDENTITY" "$FLOATER_APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    /usr/bin/codesign --force --options runtime --timestamp --sign "$CODE_SIGNING_IDENTITY" "$FLOATER_APP_BUNDLE/Contents/MacOS/floater-cli"
    /usr/bin/codesign --force --options runtime --timestamp --sign "$CODE_SIGNING_IDENTITY" "$FLOATER_APP_BUNDLE"
    verify_signing_certificate
else
    # Ad-hoc signatures change with every build, which drops the app's
    # Accessibility permission. A stable development identity keeps it.
    FLOATER_DEV_SIGNING_IDENTITY="${CODE_SIGNING_IDENTITY:-}"
    if [[ -z "$FLOATER_DEV_SIGNING_IDENTITY" ]]; then
        while IFS= read -r identity; do
            # The keychain identity list can miss recently revoked certificates.
            /usr/bin/codesign --force --sign "$identity" "$FLOATER_APP_BUNDLE"
            if verify_signing_certificate; then
                FLOATER_DEV_SIGNING_IDENTITY="$identity"
                break
            fi
            printf 'Skipping untrusted development identity %s\n' "$identity" >&2
        done < <(find_development_identities)
    else
        /usr/bin/codesign --force --sign "$FLOATER_DEV_SIGNING_IDENTITY" "$FLOATER_APP_BUNDLE"
        verify_signing_certificate
    fi

    if [[ -n "$FLOATER_DEV_SIGNING_IDENTITY" ]]; then
        printf 'Signed with development identity %s\n' "$FLOATER_DEV_SIGNING_IDENTITY"
    else
        /usr/bin/codesign --force --sign - "$FLOATER_APP_BUNDLE"
        printf 'No trusted development identity found; signed for local use.\n'
    fi
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$FLOATER_APP_BUNDLE"
printf 'Built %s\n' "$FLOATER_APP_BUNDLE"
