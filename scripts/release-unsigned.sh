#!/usr/bin/env bash
# release-unsigned.sh — build a release WITHOUT Apple Developer ID or
# notarization. Uses ad-hoc codesigning (no cert needed).
#
# Distribution is Homebrew-only: the DMG is uploaded to a GitHub Release
# and the Homebrew cask points at that asset. No Sparkle, no R2.
#
# Users installing the resulting DMG outside Homebrew will see a Gatekeeper
# warning on first launch. Two ways around it (documented in README):
#   • Right-click the .app → Open → Open Anyway
#   • Run: xattr -dr com.apple.quarantine /Applications/oh-my-just-open.app
# Homebrew Cask installs handle the quarantine flag automatically.
#
# Pre-flight (manual, before running):
#   1. Bump Config/Version.xcconfig (MARKETING_VERSION + CURRENT_PROJECT_VERSION).
#   2. git commit -am "chore: release vX.Y.Z" && git push origin main
#   3. ./scripts/release-unsigned.sh
#
# Prerequisites:
#   - Xcode + command-line tools (no signing cert required)
#   - gh CLI authenticated (only needed if you let the script create the release)
#
# Flags:
#   --dry-run          Print what would happen, do nothing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
ARCHIVE_PATH="$BUILD_DIR/oh-my-just-open.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_NAME="oh-my-just-open"
SCHEME="oh-my-just-open"
PROJECT="$PROJECT_ROOT/oh-my-just-open.xcodeproj"

DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        *) echo "[!] Unknown arg: $arg"; exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then echo "[dry-run] $*"; else "$@"; fi
}

echo "[*] oh-my-just-open release builder (UNSIGNED / ad-hoc)"
echo "[*] Project: $PROJECT_ROOT"

VERSION=$(awk -F' = ' '/^MARKETING_VERSION/ {gsub(/[ \t]/, "", $2); print $2}' "$PROJECT_ROOT/Config/Version.xcconfig")
BUILD=$(awk -F' = ' '/^CURRENT_PROJECT_VERSION/ {gsub(/[ \t]/, "", $2); print $2}' "$PROJECT_ROOT/Config/Version.xcconfig")
[[ -n "$VERSION" && -n "$BUILD" ]] || { echo "[!] Couldn't parse version from Config/Version.xcconfig"; exit 1; }

# This project lives inside the blas0/mac-os-apps monorepo, which hosts several
# projects off one tag namespace — hence the project-prefixed tag.
TAG="oh-my-just-open-v$VERSION"
echo "[*] Version: $VERSION ($BUILD)"

# ============================================================
# [0] Git pre-flight
# ============================================================
echo ""
echo "[0] Git pre-flight..."
# Scoped to this project's subtree — a sibling project being dirty in the
# monorepo is not a reason to block an oh-my-just-open release.
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain -- "$PROJECT_ROOT")" ]]; then
    echo "[!] Working tree dirty under $PROJECT_ROOT:"
    git -C "$PROJECT_ROOT" status --short -- "$PROJECT_ROOT"
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

if git -C "$PROJECT_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "[!] Tag $TAG already exists locally. Bump Config/Version.xcconfig."
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
run mkdir -p "$BUILD_DIR" "$DIST_DIR"

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
# [3] Copy .app out of the archive, re-sign ad-hoc.
# ============================================================
echo "[3] Extracting .app from archive..."
run mkdir -p "$EXPORT_PATH"
ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if ! $DRY_RUN; then
    rm -rf "$APP_PATH"
    cp -R "$ARCHIVE_APP" "$APP_PATH"
fi

echo "[3b] Ad-hoc signing .app..."
run codesign --force --deep --options runtime --sign - "$APP_PATH"
if ! $DRY_RUN; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH" || {
        echo "[!] Codesign verify failed"; exit 1;
    }
fi
echo "[+] Signed (ad-hoc): $APP_PATH"

# ============================================================
# [4] DMG
# ============================================================
echo "[4] Building DMG..."
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
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

run codesign --force --sign - "$DMG_PATH"
echo "[+] DMG: $DMG_PATH"

# ============================================================
# Done — print next steps
# ============================================================
echo ""
echo "[+] Build pipeline complete (UNSIGNED)."
echo ""
echo "Artifact: $DMG_PATH"
echo ""
echo "Next steps:"
echo ""
echo "  # Compute sha256 for the Homebrew cask:"
SHA256=""
if ! $DRY_RUN; then
    SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
    echo "  sha256: $SHA256"
fi
echo ""
echo "  # Tag and push (project-prefixed — mac-os-apps hosts several projects):"
echo "  git tag -a $TAG -m \"oh-my-just-open $VERSION\""
echo "  git push origin main --tags"
echo ""
echo "  # Create the GitHub Release (the cask URL points here):"
echo "  gh release create $TAG \\"
echo "    \"$DMG_PATH\" \\"
echo "    --title \"oh-my-just-open v$VERSION\" \\"
echo "    --notes \"See CHANGELOG.md for details.\""
echo ""
echo "  # Bump the cask in the sibling directory, then publish it to the tap repo:"
echo "  cd \"\$(git -C \\\"$PROJECT_ROOT\\\" rev-parse --show-toplevel)/homebrew-omjo\""
echo "  sed -i '' \"s/version \\\".*\\\"/version \\\"$VERSION\\\"/\" Casks/oh-my-just-open.rb"
if [[ -n "$SHA256" ]]; then
    echo "  sed -i '' \"s/sha256 \\\"[a-f0-9]*\\\"/sha256 \\\"$SHA256\\\"/\" Casks/oh-my-just-open.rb"
fi
echo "  git add Casks/oh-my-just-open.rb && git commit -m \"oh-my-just-open $VERSION\""
echo "  ./publish-tap.sh          # pushes the cask to blas0/homebrew-omjo"
echo ""
echo "Verification:"
echo "  codesign -dv --verbose=4 \"$APP_PATH\"     # should show 'adhoc' Signature"
echo "  hdiutil verify \"$DMG_PATH\""
echo "  spctl --assess --type install \"$DMG_PATH\" # expected: 'rejected (Unnotarized)' — that's fine"
