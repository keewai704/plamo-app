#!/usr/bin/env bash
set -euo pipefail

for result in .build/Logs/*.xcresult; do
  [ -e "${result}" ] || continue
  echo "### $(basename "${result}")"
  xcrun xcresulttool get test-results summary --path "${result}" 2>/dev/null || true
  echo
done
