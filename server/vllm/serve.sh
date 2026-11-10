#!/usr/bin/env bash
# Starts vLLM with the NVFP4 build of PLaMo 3 Translate 0.8B. Run through ../serve.sh.
#
# The weights stay loaded until the server stops; PLAMO_IDLE_SECONDS does not apply.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

gpu_memory="${PLAMO_GPU_MEMORY:-0.25}"
if [[ ! "${gpu_memory}" =~ ^(0?\.[0-9]+|1(\.0+)?)$ ]]; then
  echo "error: PLAMO_GPU_MEMORY must be a fraction of the GPU memory, such as 0.25" >&2
  exit 1
fi

model="${PLAMO_MODEL_DIR}/plamo-3-translate-0.8b-NVFP4"
"${here}/fetch-model.sh" "${model}"

export UV_PROJECT_ENVIRONMENT="${PLAMO_MODEL_DIR}/vllm/venv"
export UV_CACHE_DIR="${PLAMO_MODEL_DIR}/vllm/uv-cache"
export UV_PYTHON=python3.13
export UV_PYTHON_DOWNLOADS=never
uv sync --quiet --frozen --no-install-project --project "${here}"

export HF_HUB_OFFLINE=1
export HF_HOME="${PLAMO_MODEL_DIR}/vllm/huggingface"
export VLLM_NO_USAGE_STATS=1
export DO_NOT_TRACK=1
# FlashInfer compiles its sampler with nvcc at runtime, and translation does not sample.
export VLLM_USE_FLASHINFER_SAMPLER=0
# The key goes through the environment so that it stays out of `ps`.
if [[ -n "${PLAMO_API_KEY:-}" ]]; then
  export VLLM_API_KEY="${PLAMO_API_KEY}"
fi

exec "${UV_PROJECT_ENVIRONMENT}/bin/vllm" serve "${model}" \
  --trust-remote-code \
  --served-model-name plamo-3-translate \
  --host "${PLAMO_HOST}" \
  --port "${PLAMO_PORT}" \
  --max-model-len 16384 \
  --max-num-seqs 4 \
  --gpu-memory-utilization "${gpu_memory}"
