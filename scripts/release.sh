#!/usr/bin/env bash
# release.sh — build, sign, notarize, upload, and stage a release of oh-my-just-open.
#
# Pre-flight (manual, before running):
#   1. Bump Config/Version.xcconfig (MARKETING_VERSION + CURRENT_PROJECT_VERSION).
#   2. git commit -am "chore: release vX.Y.Z" && git push origin main
#   3. ./scripts/release.sh
#
# Prerequisites:
#   - Xcode + command-line tools
#   - Developer ID Application cert in login keychain
#   - Notary keychain profile: `xcrun notarytool store-credentials omjo-notary ...`
#   - Sparkle EdDSA key: scripts/generate-sparkle-key.sh
#   - awscli: brew install awscli
#   - scripts/.env.release populated (copy from .env.release.example)
#
# Flags:
#   --skip-notarize    Skip notarization (debug builds)
#   --skip-upload      Build only, no R2 upload, no GitHub release
#   --dry-run          Print what would happen, do nothing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
RELEASE_DIR="$PROJECT_ROOT/Release"
ARCHIVE_PATH="$BUILD_DIR/oh-my-just-open.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_NAME="oh-my-just-open"
SCHEME="oh-my-just-open"
PROJECT="$PROJECT_ROOT/oh-my-just-open.xcodeproj"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
SPARKLE_KEY_FILE="$HOME/.omjo-keys/sparkle_eddsa_seed.txt"
NOTARY_PROFILE="${NOTARY_PROFILE:-omjo-notary}"

# Parse flags
SKIP_NOTARIZE=false
SKIP_UPLOAD=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --skip-upload)   SKIP_UPLOAD=true ;;
        --dry-run)       DRY_RUN=true ;;
        *) echo "[!] Unknown arg: $arg"; exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then echo "[dry-run] $*"; else "$@"; fi
}

echo "[*] oh-my-just-open release builder"
echo "[*] Project: $PROJECT_ROOT"

# Load R2 settings. The vanity URL is public (it's baked into the appcast
# Sparkle reads) so we need it for step 8 even when --skip-upload is set.
# Secrets are only required when actually uploading.
if [[ -f "$SCRIPT_DIR/.env.release" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env.release"
elif [[ -f "$SCRIPT_DIR/.env.release.example" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env.release.example"
fi
: "${R2_VANITY_URL:?R2_VANITY_URL missing in scripts/.env.release(.example)}"

if [[ "$SKIP_UPLOAD" == "false" ]]; then
    if [[ ! -f "$SCRIPT_DIR/.env.release" ]]; then
        echo "[!] scripts/.env.release not found. Copy from .env.release.example and fill in R2 creds."
        echo "[!] Or rerun with --skip-upload."
        exit 1
    fi
    : "${R2_ACCESS_KEY_ID:?missing in .env.release}"
    : "${R2_SECRET_ACCESS_KEY:?missing in .env.release}"
    : "${R2_ACCOUNT_ID:?missing in .env.release}"
    : "${R2_BUCKET:?missing in .env.release}"
    R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
fi

# Read version from xcconfig (single source of truth)
VERSION=$(awk -F' = ' '/^MARKETING_VERSION/ {gsub(/[ \t]/, "", $2); print $2}' "$PROJECT_ROOT/Config/Version.xcconfig")
BUILD=$(awk -F' = ' '/^CURRENT_PROJECT_VERSION/ {gsub(/[ \t]/, "", $2); print $2}' "$PROJECT_ROOT/Config/Version.xcconfig")
[[ -n "$VERSION" && -n "$BUILD" ]] || { echo "[!] Couldn't parse version from Config/Version.xcconfig"; exit 1; }
echo "[*] Version: $VERSION ($BUILD)"

# ============================================================
# [0] Git pre-flight
# ============================================================
echo ""
echo "[0] Git pre-flight..."
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain)" ]]; then
    echo "[!] Working tree dirty:"
    git -C "$PROJECT_ROOT" status --short
    echo "    Commit or stash before releasing."
    exit 1
fi
echo "    [+] Working tree clean"

CURRENT_BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "    [!] On branch '$CURRENT_BRANCH', not main."
    read -p "    Continue? [y/N] " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] || { echo "    Aborted."; exit 1; }
fi

if git -C "$PROJECT_ROOT" rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "[!] Tag v$VERSION already exists locally. Bump Config/Version.xcconfig."
    exit 1
fi

git -C "$PROJECT_ROOT" fetch --quiet --tags origin "$CURRENT_BRANCH" 2>/dev/null || true
LOCAL=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
REMOTE=$(git -C "$PROJECT_ROOT" rev-parse "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")
if [[ -n "$REMOTE" && "$LOCAL" != "$REMOTE" ]]; then
    echo "    [!] Local out of sync with origin/$CURRENT_BRANCH."
    read -p "    Continue anyway? [y/N] " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi
echo "[+] Git checks passed"

# ============================================================
# [1] Clean
# ============================================================
echo ""
echo "[1] Cleaning build dir..."
run rm -rf "$BUILD_DIR"
run mkdir -p "$BUILD_DIR" "$RELEASE_DIR"

# ============================================================
# [2] Archive
# ============================================================
echo "[2] Archiving (Release / Developer ID)..."
run_archive() {
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -allowProvisioningUpdates
}
if $DRY_RUN; then
    echo "[dry-run] xcodebuild archive ..."
elif command -v xcbeautify >/dev/null 2>&1; then
    set -o pipefail; run_archive | xcbeautify; set +o pipefail
else
    run_archive
fi

# ============================================================
# [3] Export
# ============================================================
echo "[3] Exporting signed .app..."
run xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if ! $DRY_RUN && [[ ! -d "$APP_PATH" ]]; then
    echo "[!] Export failed — .app not at $APP_PATH"
    exit 1
fi
echo "[+] Exported: $APP_PATH"

# ============================================================
# [4] Notarize + staple
# ============================================================
if [[ "$SKIP_NOTARIZE" == "false" ]]; then
    echo "[4] Notarizing..."
    NOTARIZE_ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
    run ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
    run xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    run xcrun stapler staple "$APP_PATH"
    echo "[+] Notarized + stapled"
else
    echo "[4] Skipping notarization (--skip-notarize)"
fi

# ============================================================
# [5] DMG
# ============================================================
echo "[5] Building DMG..."
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
DMG_STAGING="$BUILD_DIR/dmg-staging"
run rm -f "$DMG_PATH"
run rm -rf "$DMG_STAGING"
run mkdir -p "$DMG_STAGING"
if ! $DRY_RUN; then
    cp -R "$APP_PATH" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
fi
run hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

# Sign + staple the DMG itself so Gatekeeper trusts it without an internet check.
if [[ "$SKIP_NOTARIZE" == "false" ]]; then
    SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Neurix (83698ZGFJP)}"
    run codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
    # Notarize the DMG (separate submission — staples after).
    run xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    run xcrun stapler staple "$DMG_PATH"
fi
echo "[+] DMG: $DMG_PATH"

# ============================================================
# [6] Sparkle ZIP
# ============================================================
echo "[6] Building Sparkle ZIP..."
ZIP_NAME="$APP_NAME-$VERSION.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
run rm -f "$ZIP_PATH"
run ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "[+] ZIP: $ZIP_PATH"

# ============================================================
# [7] Sparkle EdDSA signature
# ============================================================
echo "[7] Signing for Sparkle..."
SPARKLE_SIGN=""
DERIVED_DATA_BUILD_DIR=$(xcodebuild -project "$PROJECT" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*BUILD_DIR/ {gsub(/^ +| +$/, "", $2); print $2; exit}')
if [[ -n "$DERIVED_DATA_BUILD_DIR" ]]; then
    DERIVED_ROOT="$(dirname "$(dirname "$DERIVED_DATA_BUILD_DIR")")"
    if [[ -x "$DERIVED_ROOT/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" ]]; then
        SPARKLE_SIGN="$DERIVED_ROOT/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
    fi
fi
if [[ -z "$SPARKLE_SIGN" ]]; then
    SPARKLE_SIGN=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "sign_update" -type f -perm +111 2>/dev/null | head -1)
fi

ED_SIGNATURE=""
LENGTH=""
if [[ -n "$SPARKLE_SIGN" && -x "$SPARKLE_SIGN" && -f "$SPARKLE_KEY_FILE" ]]; then
    if $DRY_RUN; then
        echo "[dry-run] $SPARKLE_SIGN --ed-key-file $SPARKLE_KEY_FILE $ZIP_PATH"
        ED_SIGNATURE="DRYRUN_SIGNATURE"
        LENGTH="0"
    else
        SIG_OUT=$("$SPARKLE_SIGN" --ed-key-file "$SPARKLE_KEY_FILE" "$ZIP_PATH" 2>&1)
        ED_SIGNATURE=$(echo "$SIG_OUT" | grep -o 'edSignature="[^"]*"' | cut -d'"' -f2)
        LENGTH=$(stat -f%z "$ZIP_PATH")
    fi
    echo "[+] Signed for Sparkle"
else
    echo "[!] Sparkle sign_update or EdDSA key missing — appcast entry will be unsigned."
    echo "    sign_update: ${SPARKLE_SIGN:-not found}"
    echo "    key file:    $SPARKLE_KEY_FILE"
fi

# ============================================================
# [8] Update appcast.xml
# ============================================================
echo "[8] Updating appcast.xml..."
PUB_DATE=$(LC_ALL=C date -R)
NEW_ITEM=$(cat << APPCAST_ITEM
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <enclosure url="$R2_VANITY_URL/releases/$ZIP_NAME"
                       sparkle:edSignature="$ED_SIGNATURE"
                       length="$LENGTH"
                       type="application/octet-stream"/>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
        </item>
APPCAST_ITEM
)

if ! $DRY_RUN; then
    NEW_ITEM_FILE="$BUILD_DIR/new_item.xml"
    echo "$NEW_ITEM" > "$NEW_ITEM_FILE"
    awk '
        /<language>.*<\/language>/ {
            print
            while ((getline line < "'"$NEW_ITEM_FILE"'") > 0) { print line }
            next
        }
        { print }
    ' "$APPCAST_PATH" > "$APPCAST_PATH.tmp"
    mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"
    rm -f "$NEW_ITEM_FILE"
fi
echo "[+] appcast.xml updated"

# ============================================================
# [9] Upload to R2
# ============================================================
if [[ "$SKIP_UPLOAD" == "false" ]]; then
    echo "[9] Uploading to R2..."
    export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="auto"

    run aws s3 cp "$ZIP_PATH" "s3://$R2_BUCKET/releases/$ZIP_NAME" \
        --endpoint-url "$R2_ENDPOINT" --content-type "application/zip"
    run aws s3 cp "$DMG_PATH" "s3://$R2_BUCKET/releases/$DMG_NAME" \
        --endpoint-url "$R2_ENDPOINT" --content-type "application/x-apple-diskimage"
    run aws s3 cp "$DMG_PATH" "s3://$R2_BUCKET/releases/$APP_NAME-latest.dmg" \
        --endpoint-url "$R2_ENDPOINT" \
        --content-type "application/x-apple-diskimage" \
        --cache-control "max-age=300"
    run aws s3 cp "$APPCAST_PATH" "s3://$R2_BUCKET/appcast.xml" \
        --endpoint-url "$R2_ENDPOINT" \
        --content-type "application/xml" \
        --cache-control "max-age=300"

    echo "[+] Uploaded:"
    echo "    $R2_VANITY_URL/appcast.xml"
    echo "    $R2_VANITY_URL/releases/$ZIP_NAME"
    echo "    $R2_VANITY_URL/releases/$DMG_NAME"
    echo "    $R2_VANITY_URL/releases/$APP_NAME-latest.dmg   (stable pointer, max-age=300)"
else
    echo "[9] Skipping upload (--skip-upload)"
fi

# ============================================================
# Done — print next steps
# ============================================================
echo ""
echo "[+] Build pipeline complete."
echo ""
echo "Artifacts in $RELEASE_DIR:"
ls -lh "$RELEASE_DIR" 2>/dev/null || true
echo ""
echo "Next steps (run manually so you can inspect appcast.xml first):"
echo ""
echo "  git add Release/appcast.xml"
echo "  git commit -m \"release: v$VERSION\""
echo "  git tag -a v$VERSION -m \"Release $VERSION\""
echo "  git push origin main --tags"
echo ""
echo "  gh release create v$VERSION \\"
echo "    \"$RELEASE_DIR/$DMG_NAME\" \\"
echo "    --title \"v$VERSION\" \\"
echo "    --notes \"See CHANGELOG.md for details.\""
echo ""
echo "Verification:"
echo "  spctl --assess --type install \"$DMG_PATH\""
echo "  xcrun stapler validate \"$DMG_PATH\""
echo "  curl -sI $R2_VANITY_URL/releases/$APP_NAME-latest.dmg"
