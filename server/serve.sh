#!/usr/bin/env bash
# Starts llama-server with PLaMo 3 Translate 0.8B.
#
# Settings come from the environment, then from the config file
# (PLAMO_CONFIG, default ~/.config/plamo-server/config.env; see config.example.env).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=model.env
. "${here}/model.env"

config="${PLAMO_CONFIG:-${XDG_CONFIG_HOME:-${HOME}/.config}/plamo-server/config.env}"
if [[ -f "${config}" ]]; then
  while IFS='=' read -r key value || [[ -n "${key}" ]]; do
    key="${key//[[:space:]]/}"
    if [[ -z "${key}" || "${key}" == \#* ]]; then
      continue
    fi
    if [[ ! "${key}" =~ ^PLAMO_(HOST|PORT|API_KEY|GPU_LAYERS|IDLE_SECONDS|MODEL_DIR)$ ]]; then
      echo "error: unknown setting ${key} in ${config}" >&2
      exit 1
    fi
    if [[ -z "${!key+set}" ]]; then
      export "${key}=${value}"
    fi
  done < "${config}"
fi

host="${PLAMO_HOST:-127.0.0.1}"
port="${PLAMO_PORT:-8000}"
idle_seconds="${PLAMO_IDLE_SECONDS:-600}"
export PLAMO_MODEL_DIR="${PLAMO_MODEL_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/plamo-server/models}"

if [[ ! "${idle_seconds}" =~ ^[0-9]+$ ]]; then
  echo "error: PLAMO_IDLE_SECONDS must be 0 (keep loaded) or a number of seconds" >&2
  exit 1
fi

case "${host}" in
  127.*|localhost|::1) ;;
  *)
    if [[ -z "${PLAMO_API_KEY:-}" ]]; then
      echo "error: set PLAMO_API_KEY when binding to ${host}" >&2
      exit 1
    fi
    ;;
esac

if command -v llama-server >/dev/null 2>&1; then
  llama_server=llama-server
elif [[ -x "${here}/.bin/llama-server" ]]; then
  llama_server="${here}/.bin/llama-server"
  export LD_LIBRARY_PATH="${here}/.bin${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
else
  echo "error: llama-server not found; run server/install-llama.sh" >&2
  exit 1
fi

"${here}/fetch-model.sh"

# The key goes through the environment so that it stays out of `ps`.
if [[ -n "${PLAMO_API_KEY:-}" ]]; then
  export LLAMA_API_KEY="${PLAMO_API_KEY}"
fi

args=(
  -m "${PLAMO_MODEL_DIR}/${PLAMO_MODEL_FILE}"
  --host "${host}"
  --port "${port}"
  --alias plamo-3-translate
  --ctx-size 16384
  --parallel 4
  --jinja
  --no-webui
)
if [[ -n "${PLAMO_GPU_LAYERS:-}" ]]; then
  args+=(--gpu-layers "${PLAMO_GPU_LAYERS}")
fi
if (( 10#${idle_seconds} > 0 )); then
  args+=(--sleep-idle-seconds "${idle_seconds}")
fi

exec "${llama_server}" "${args[@]}"
