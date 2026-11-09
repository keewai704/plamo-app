#!/usr/bin/env bash
# Downloads the pinned GGUF into PLAMO_MODEL_DIR and verifies its checksum.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=model.env
. "${here}/model.env"

model_dir="${PLAMO_MODEL_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/plamo-server/models}"
target="${model_dir}/${PLAMO_MODEL_FILE}"
mkdir -p "${model_dir}"

verify() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "${PLAMO_MODEL_SHA256}  $1" | sha256sum -c --status -
  else
    echo "${PLAMO_MODEL_SHA256}  $1" | shasum -a 256 -c --status -
  fi
}

if [[ -f "${target}" ]] && verify "${target}"; then
  exit 0
fi

curl -fL --retry 5 --retry-all-errors -C - -o "${target}.part" \
  "https://huggingface.co/${PLAMO_HF_REPO}/resolve/${PLAMO_HF_REVISION}/${PLAMO_MODEL_FILE}"

if ! verify "${target}.part"; then
  rm -f "${target}.part"
  echo "error: checksum mismatch for ${PLAMO_MODEL_FILE}" >&2
  exit 1
fi
mv "${target}.part" "${target}"
