#!/usr/bin/env bash
# release-unsigned.sh — build and ship a release WITHOUT Apple Developer ID
# or notarization. Uses ad-hoc codesigning (no cert needed) so Sparkle's
# update verification still works.
#
# Users installing the resulting DMG will see a Gatekeeper warning on first
# launch. Two ways around it (document in README):
#   • Right-click the .app → Open → Open Anyway
#   • Run: xattr -dr com.apple.quarantine /Applications/oh-my-just-open.app
# Homebrew Cask installs handle the quarantine flag automatically.
#
# Sparkle in-app updates still work — they verify against the EdDSA key in
# Info.plist, which is independent of Apple notarization.
#
# Pre-flight (manual, before running):
#   1. Bump Config/Version.xcconfig (MARKETING_VERSION + CURRENT_PROJECT_VERSION).
#   2. git commit -am "chore: release vX.Y.Z" && git push origin main
#   3. ./scripts/release-unsigned.sh
#
# Prerequisites:
#   - Xcode + command-line tools (no signing cert required)
#   - Sparkle EdDSA key: scripts/generate-sparkle-key.sh
#   - awscli: brew install awscli
#   - scripts/.env.release populated (R2 creds; SIGNING_IDENTITY unused)
#
# Flags:
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

# Parse flags
SKIP_UPLOAD=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --skip-upload)   SKIP_UPLOAD=true ;;
        --dry-run)       DRY_RUN=true ;;
        *) echo "[!] Unknown arg: $arg"; exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then echo "[dry-run] $*"; else "$@"; fi
}

echo "[*] oh-my-just-open release builder (UNSIGNED / ad-hoc)"
echo "[*] Project: $PROJECT_ROOT"

# Load R2 settings (vanity URL is needed for the appcast even with --skip-upload).
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
# [2] Archive (no provisioning — sign manually after export)
# ============================================================
echo "[2] Archiving (Release, no signing identity)..."
run_archive() {
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGNING_REQUIRED=YES \
        CODE_SIGNING_ALLOWED=YES \
        DEVELOPMENT_TEAM=""
}
if $DRY_RUN; then
    echo "[dry-run] xcodebuild archive (ad-hoc) ..."
elif command -v xcbeautify >/dev/null 2>&1; then
    set -o pipefail; run_archive | xcbeautify; set +o pipefail
else
    run_archive
fi

# ============================================================
# [3] Copy .app out of the archive (no -exportArchive — that requires
#     ExportOptions + a real signing identity).
# ============================================================
echo "[3] Extracting .app from archive..."
run mkdir -p "$EXPORT_PATH"
ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if ! $DRY_RUN; then
    rm -rf "$APP_PATH"
    cp -R "$ARCHIVE_APP" "$APP_PATH"
fi

# Re-sign deep with ad-hoc identity (`-`) so Sparkle can verify the bundle
# at update time. Hardened Runtime still on so the runtime entitlements stick.
echo "[3b] Ad-hoc signing .app..."
run codesign --force --deep --options runtime --sign - "$APP_PATH"
if ! $DRY_RUN; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH" || {
        echo "[!] Codesign verify failed"; exit 1;
    }
fi
echo "[+] Signed (ad-hoc): $APP_PATH"

# ============================================================
# [4] (Notarization skipped — no Apple Developer agreement.)
# ============================================================
echo "[4] Skipping notarization (unsigned release)"

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

# Ad-hoc sign the DMG too (cheap, helps a few download mechanisms).
run codesign --force --sign - "$DMG_PATH"
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
# [7] Sparkle EdDSA signature (REQUIRED — this is how update integrity
#     is proven without Apple notarization)
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
    echo "[!] Sparkle sign_update or EdDSA key missing — refusing to ship an"
    echo "    unsigned update. Without the EdDSA signature there is no integrity"
    echo "    check at all on the update payload. Run scripts/generate-sparkle-key.sh"
    echo "    or build the project in Xcode once so the Sparkle package resolves."
    exit 1
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
echo "[+] Build pipeline complete (UNSIGNED)."
echo ""
echo "Artifacts in $RELEASE_DIR:"
ls -lh "$RELEASE_DIR" 2>/dev/null || true
echo ""
echo "Next steps:"
echo ""
echo "  git add Release/appcast.xml"
echo "  git commit -m \"release: v$VERSION\""
echo "  git tag -a v$VERSION -m \"Release $VERSION\""
echo "  git push origin main --tags"
echo ""
echo "  # Compute sha256 for the Homebrew cask:"
echo "  shasum -a 256 \"$RELEASE_DIR/$DMG_NAME\""
echo ""
echo "  gh release create v$VERSION \\"
echo "    \"$RELEASE_DIR/$DMG_NAME\" \\"
echo "    --title \"v$VERSION\" \\"
echo "    --notes \"See CHANGELOG.md for details.\""
echo ""
echo "Then update homebrew-tap/Casks/oh-my-just-open.rb (version + sha256) and push."
echo ""
echo "Verification:"
echo "  codesign -dv --verbose=4 \"$APP_PATH\"     # should show 'adhoc' Signature"
echo "  spctl --assess --type install \"$DMG_PATH\" # expected: 'rejected (Unnotarized)'"
echo "  curl -sI $R2_VANITY_URL/releases/$APP_NAME-latest.dmg"
