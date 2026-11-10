#!/usr/bin/env bash
# Installs the pinned CPU build of llama.cpp into server/.bin.
# Linux x64 and macOS arm64 only; use a system package for GPU builds.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=model.env
. ./model.env

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) platform=ubuntu-x64 ;;
  Darwin-arm64) platform=macos-arm64 ;;
  *) echo "error: no prebuilt llama.cpp for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

[[ -x .bin/llama-server ]] && exit 0

archive="$(mktemp)"
trap 'rm -f "${archive}"' EXIT
curl -fL --retry 5 --retry-all-errors -o "${archive}" \
  "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_CPP_TAG}/llama-${LLAMA_CPP_TAG}-bin-${platform}.tar.gz"
mkdir -p .bin
tar -xzf "${archive}" --strip-components=1 -C .bin
