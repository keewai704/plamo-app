#!/usr/bin/env bash
# Checks a running server started with a short PLAMO_IDLE_SECONDS: the weights are
# released even while clients poll the status, and the next request loads them again.
#   usage: test-idle.sh [base-url]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
base="${1:-http://127.0.0.1:8000}"

sleeping() {
  curl -fsS -H "Authorization: Bearer ${PLAMO_API_KEY:-none}" "${base}/props" |
    python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["is_sleeping"] else 1)'
}

for _ in $(seq 1 60); do
  if sleeping; then
    echo "released the weights"
    "${here}/smoke.sh" "${base}"
    if sleeping; then
      echo "error: still sleeping right after a translation" >&2
      exit 1
    fi
    exit 0
  fi
  sleep 1
done

echo "error: the server never released the weights" >&2
exit 1
