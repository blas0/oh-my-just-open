#!/usr/bin/env bash
# Generate the Sparkle EdDSA keypair used to sign release artifacts.
# Run ONCE. The private seed must never leave ~/.omjo-keys/ or be committed.
set -euo pipefail

KEY_DIR="${HOME}/.omjo-keys"
SEED_FILE="${KEY_DIR}/sparkle_eddsa_seed.txt"
PUBLIC_FILE="${KEY_DIR}/sparkle_eddsa_public.txt"

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

if [[ -f "${SEED_FILE}" ]]; then
  echo "[!] ${SEED_FILE} already exists — refusing to overwrite."
  echo "    Public key:"
  cat "${PUBLIC_FILE}"
  exit 1
fi

# Sparkle's generate_keys lives inside the resolved SwiftPM checkout.
DERIVED_DATA="$(xcodebuild -project oh-my-just-open.xcodeproj -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/BUILD_DIR/ {print $2; exit}')"
SPARKLE_BIN="$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
  -name "generate_keys" -path "*Sparkle*" -type f 2>/dev/null | head -1)"

if [[ -z "${SPARKLE_BIN}" ]]; then
  echo "[!] Couldn't locate Sparkle's generate_keys binary."
  echo "    Open the project in Xcode and let SwiftPM resolve the Sparkle package first."
  exit 1
fi

# 1) Create the keypair in the login Keychain (no-op if one already lives there).
"${SPARKLE_BIN}"
# 2) Export the private seed so it can be backed up off-Keychain.
"${SPARKLE_BIN}" -x "${SEED_FILE}"
# 3) Read the public key out of the Keychain.
"${SPARKLE_BIN}" -p > "${PUBLIC_FILE}"

chmod 600 "${SEED_FILE}" "${PUBLIC_FILE}"

echo "[ok] Wrote:"
echo "     ${SEED_FILE}     (private, NEVER commit)"
echo "     ${PUBLIC_FILE}"
echo
echo "Public key (paste into Config/Distribution.xcconfig as SUPublicEDKey):"
echo
cat "${PUBLIC_FILE}"
