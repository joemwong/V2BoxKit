#!/usr/bin/env bash
set -euo pipefail

VERSION="v26.7.28"
ARCHIVE="libxray-android.zip"
EXPECTED_SHA256="28b7dc9d6cc8455fcca5cbd56e387003a7bfb558128651a64899dc3a8ccff666"
URL="https://github.com/XTLS/libXray/releases/download/${VERSION}/${ARCHIVE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_DIR}/android/app/libs"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}
trap cleanup EXIT

curl -fL "${URL}" -o "${TEMP_DIR}/${ARCHIVE}"

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(sha256sum "${TEMP_DIR}/${ARCHIVE}" | awk '{print $1}')"
else
  ACTUAL_SHA256="$(shasum -a 256 "${TEMP_DIR}/${ARCHIVE}" | awk '{print $1}')"
fi

if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  echo "libXray checksum mismatch" >&2
  echo "expected: ${EXPECTED_SHA256}" >&2
  echo "actual:   ${ACTUAL_SHA256}" >&2
  exit 1
fi

unzip -q "${TEMP_DIR}/${ARCHIVE}" -d "${TEMP_DIR}/unpacked"
mkdir -p "${OUTPUT_DIR}"
cp "${TEMP_DIR}/unpacked/libxray-android/libXray.aar" \
  "${OUTPUT_DIR}/libXray.aar"

echo "Installed ${OUTPUT_DIR}/libXray.aar (${VERSION})"
