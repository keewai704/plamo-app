#!/usr/bin/env bash
# Downloads the pinned NVFP4 model into PLAMO_MODEL_DIR and verifies every file.
#   usage: fetch-model.sh <target-dir>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=vllm/model.env
. "${here}/model.env"

target="$1"
mkdir -p "${target}"

while read -r sha256 file; do
  if [[ -f "${target}/${file}" ]] && echo "${sha256}  ${target}/${file}" | sha256sum -c --status -; then
    continue
  fi
  curl -fL --retry 5 --retry-all-errors -C - -o "${target}/${file}.part" \
    "https://huggingface.co/${PLAMO_NVFP4_REPO}/resolve/${PLAMO_NVFP4_REVISION}/${file}"
  if ! echo "${sha256}  ${target}/${file}.part" | sha256sum -c --status -; then
    rm -f "${target}/${file}.part"
    echo "error: checksum mismatch for ${file}" >&2
    exit 1
  fi
  mv "${target}/${file}.part" "${target}/${file}"
done < "${here}/model.sha256"
