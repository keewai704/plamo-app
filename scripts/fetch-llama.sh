#!/usr/bin/env bash
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-b12121}"
LLAMA_SHA256="${LLAMA_SHA256:-00bc6fec00beba802a3912a6afb81e1678da5248a6a92548a9ce66724a3e7638}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/vendor/llama"
ARCHIVE="${ROOT}/.build/llama/llama-${LLAMA_TAG}-xcframework.zip"

if [ -d "${DEST}/llama.xcframework/ios-arm64/llama.framework" ]; then
  echo "llama.xcframework already present at ${DEST}"
  exit 0
fi

mkdir -p "$(dirname "${ARCHIVE}")" "${DEST}"

if [ ! -f "${ARCHIVE}" ]; then
  echo "Downloading llama.cpp ${LLAMA_TAG} xcframework…"
  curl -fL --retry 3 --retry-delay 2 -o "${ARCHIVE}.part" \
    "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-xcframework.zip"
  mv "${ARCHIVE}.part" "${ARCHIVE}"
fi

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"
else
  echo "error: no sha256 tool found" >&2
  exit 1
fi

if [ "${ACTUAL}" != "${LLAMA_SHA256}" ]; then
  echo "error: checksum mismatch for ${ARCHIVE}" >&2
  echo "  expected: ${LLAMA_SHA256}" >&2
  echo "  actual:   ${ACTUAL}" >&2
  rm -f "${ARCHIVE}"
  exit 1
fi

rm -rf "${DEST}/extract"
mkdir -p "${DEST}/extract"

if command -v ditto >/dev/null 2>&1; then
  ditto -x -k "${ARCHIVE}" "${DEST}/extract"
else
  python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "${ARCHIVE}" "${DEST}/extract"
fi

if [ ! -d "${DEST}/extract/build-apple/llama.xcframework" ]; then
  echo "error: unexpected archive layout" >&2
  exit 1
fi

mv "${DEST}/extract/build-apple/llama.xcframework" "${DEST}/llama.xcframework"
rm -rf "${DEST}/extract"
echo "llama.xcframework ready: ${DEST}/llama.xcframework"
