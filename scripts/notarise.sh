#!/bin/bash
#
# scripts/notarise.sh: build a Release NAKL.app, sign it with the user's
# Developer ID Application identity, package as a DMG, submit to Apple's
# notary service, and staple the result. Per SPEC-0010 § Group A.
#
# Preconditions (validated below):
#   1. A `Developer ID Application` certificate in the user's login keychain.
#   2. A notarytool keychain profile (default name: NAKL_NOTARY) created via
#      `xcrun notarytool store-credentials NAKL_NOTARY` (one-time).
#   3. Hardened Runtime enabled in the project (already on per SPEC-0005).
#   4. Info.plist has CFBundleVersion and CFBundleShortVersionString.
#
# Environment variable overrides:
#   DEVELOPER_ID         e.g. "Developer ID Application: Han Ngo (ABCDE12345)"
#                        Default: first matching identity from `security find-identity`.
#   NAKL_NOTARY_PROFILE  Default: NAKL_NOTARY
#   NAKL_VERSION         Default: read from NAKL/NAKL-Info.plist
#   OUTPUT_DIR           Default: build/notarise/dist/<NAKL_VERSION>/
#
# Usage:
#   scripts/notarise.sh           # full pipeline
#   scripts/notarise.sh --check   # preconditions only, no build
#

set -euo pipefail

# ---- arg parsing ------------------------------------------------------------

CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=1
fi

# ---- repo paths -------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="NAKL.xcodeproj"
SCHEME="NAKL"
INFOPLIST="NAKL/NAKL-Info.plist"
ENTITLEMENTS="NAKL/NAKL.entitlements"

# ---- defaults ---------------------------------------------------------------

NAKL_NOTARY_PROFILE="${NAKL_NOTARY_PROFILE:-NAKL_NOTARY}"
NAKL_VERSION="${NAKL_VERSION:-}"
DEVELOPER_ID="${DEVELOPER_ID:-}"
OUTPUT_DIR="${OUTPUT_DIR:-}"

# ---- preconditions ----------------------------------------------------------

precheck_failed=0

require() {
    local what="$1"; local how="$2"
    if [[ "$how" == "fail" ]]; then
        echo "  ✗ $what" >&2
        precheck_failed=1
    else
        echo "  ✓ $what"
    fi
}

echo "==> Preconditions"

# 1. Identity
if [[ -z "$DEVELOPER_ID" ]]; then
    DEVELOPER_ID="$(security find-identity -v -p codesigning login.keychain \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$DEVELOPER_ID" ]]; then
    require "Developer ID Application identity in login keychain (set DEVELOPER_ID)" fail
else
    require "Developer ID identity: $DEVELOPER_ID" ok
fi

# 2. Notary profile
if ! xcrun notarytool history --keychain-profile "$NAKL_NOTARY_PROFILE" >/dev/null 2>&1; then
    require "notarytool keychain profile '$NAKL_NOTARY_PROFILE' (create with: xcrun notarytool store-credentials $NAKL_NOTARY_PROFILE)" fail
else
    require "notarytool keychain profile: $NAKL_NOTARY_PROFILE" ok
fi

# 3. Hardened runtime + entitlements
if ! grep -q "ENABLE_HARDENED_RUNTIME = YES" "$PROJECT/project.pbxproj"; then
    require "ENABLE_HARDENED_RUNTIME = YES in project (SPEC-0005)" fail
else
    require "Hardened Runtime enabled" ok
fi
if [[ ! -f "$ENTITLEMENTS" ]]; then
    require "$ENTITLEMENTS exists" fail
else
    require "Entitlements file: $ENTITLEMENTS" ok
fi

# 4. Info.plist completeness
for key in CFBundleVersion CFBundleShortVersionString CFBundleIdentifier; do
    if ! /usr/libexec/PlistBuddy -c "Print :$key" "$INFOPLIST" >/dev/null 2>&1; then
        require "$INFOPLIST has $key" fail
    else
        require "Info.plist has $key" ok
    fi
done

# 5. Version
if [[ -z "$NAKL_VERSION" ]]; then
    NAKL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFOPLIST" 2>/dev/null || true)"
fi
if [[ -z "$NAKL_VERSION" ]]; then
    require "NAKL_VERSION resolved (set env var, or fix Info.plist)" fail
else
    require "Version: $NAKL_VERSION" ok
fi

if [[ "$precheck_failed" -ne 0 ]]; then
    echo "" >&2
    echo "Preconditions failed. Fix the above and rerun." >&2
    exit 1
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo ""
    echo "==> --check passed. Skipping build/sign/notarise."
    exit 0
fi

# ---- output paths -----------------------------------------------------------

OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build/notarise/dist/$NAKL_VERSION}"
DERIVED="$REPO_ROOT/build/notarise/derived"
mkdir -p "$OUTPUT_DIR" "$DERIVED"
APP_OUT="$OUTPUT_DIR/NAKL.app"
DMG_OUT="$OUTPUT_DIR/NAKL.dmg"
DMG_STAGE="$REPO_ROOT/build/notarise/stage-$NAKL_VERSION"

# Idempotency: clean the output app, but keep the DMG until stapler runs
# successfully so a re-run can re-staple without re-notarising.
rm -rf "$APP_OUT" "$DMG_STAGE"

# ---- build Release ----------------------------------------------------------

echo ""
echo "==> Building Release configuration"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    build \
    | xcbeautify 2>/dev/null || \
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    build

BUILT_APP="$DERIVED/Build/Products/Release/NAKL.app"
test -d "$BUILT_APP" || { echo "build did not produce $BUILT_APP" >&2; exit 1; }

cp -R "$BUILT_APP" "$APP_OUT"

# ---- re-sign with Developer ID ---------------------------------------------

echo ""
echo "==> Signing with Developer ID"
codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVELOPER_ID" \
    "$APP_OUT"

codesign --verify --strict --verbose=2 "$APP_OUT"

# ---- package DMG ------------------------------------------------------------

echo ""
echo "==> Packaging DMG"
mkdir -p "$DMG_STAGE"
cp -R "$APP_OUT" "$DMG_STAGE/NAKL.app"
ln -s /Applications "$DMG_STAGE/Applications"
rm -f "$DMG_OUT"
hdiutil create \
    -volname "NAKL $NAKL_VERSION" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_OUT"
rm -rf "$DMG_STAGE"

# ---- notarise ---------------------------------------------------------------

echo ""
echo "==> Submitting to Apple notary service (this can take a few minutes)"
if ! xcrun notarytool submit "$DMG_OUT" \
        --keychain-profile "$NAKL_NOTARY_PROFILE" \
        --wait; then
    echo "" >&2
    echo "Notarisation FAILED. Last submission log:" >&2
    LAST_ID="$(xcrun notarytool history --keychain-profile "$NAKL_NOTARY_PROFILE" \
        --output-format json 2>/dev/null | python3 -c \
        'import json,sys;data=json.load(sys.stdin);print(data["history"][0]["id"])' \
        2>/dev/null || true)"
    if [[ -n "$LAST_ID" ]]; then
        xcrun notarytool log "$LAST_ID" --keychain-profile "$NAKL_NOTARY_PROFILE" >&2 || true
    fi
    exit 1
fi

# ---- staple -----------------------------------------------------------------

echo ""
echo "==> Stapling"
xcrun stapler staple "$DMG_OUT"
xcrun stapler staple "$APP_OUT"

# ---- verify ----------------------------------------------------------------

echo ""
echo "==> Verifying"
xcrun stapler validate "$DMG_OUT"
xcrun stapler validate "$APP_OUT"
spctl --assess --type execute --verbose=4 "$APP_OUT"

echo ""
echo "==> Done."
echo "  App: $APP_OUT"
echo "  DMG: $DMG_OUT"
echo ""
echo "Distribute the DMG (e.g. attach to a GitHub Release tagged v$NAKL_VERSION)."
