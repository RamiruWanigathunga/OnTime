#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
OUT_PATH="${2:-}"

if [[ -z "${APP_PATH}" ]]; then
  echo "Usage: $0 /path/to/OnTime.app [output.dmg]" >&2
  exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found: ${APP_PATH}" >&2
  exit 1
fi

if [[ -z "${OUT_PATH}" ]]; then
  mkdir -p dist
  OUT_PATH="dist/OnTime.dmg"
fi

mkdir -p "$(dirname "${OUT_PATH}")"

VOLUME_NAME="OnTime"
STAGING_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

if [[ -f "${OUT_PATH}" ]]; then
  rm -f "${OUT_PATH}"
fi

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${OUT_PATH}"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --sign "${SIGNING_IDENTITY}" "${OUT_PATH}"
  echo "Signed ${OUT_PATH}"
else
  echo "Created unsigned ${OUT_PATH} (set SIGNING_IDENTITY to codesign)."
fi
