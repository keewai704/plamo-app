#!/usr/bin/env bash
# Checks a running server: the API key is enforced and a real translation comes back.
#   usage: smoke.sh [base-url]
set -euo pipefail

base="${1:-http://127.0.0.1:8000}"

if [[ -n "${PLAMO_API_KEY:-}" ]]; then
  status="$(curl -s -o /dev/null -w '%{http_code}' "${base}/v1/models")"
  if [[ "${status}" != 401 ]]; then
    echo "error: expected 401 without an API key, got ${status}" >&2
    exit 1
  fi
fi

translation="$(curl -fsS "${base}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${PLAMO_API_KEY:-none}" \
  -d '{
    "model": "plamo-3-translate",
    "messages": [{"role": "user", "content": "会議は来週の月曜日に変更されました。"}],
    "chat_template_kwargs": {"target_lang": "en"},
    "temperature": 0,
    "max_tokens": 64,
    "stop": ["<|plamo:tag|>", "<|plamo:bos|>"]
  }' | python3 -c 'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"]["content"])')"

echo "${translation}"
grep -qi monday <<<"${translation}"
