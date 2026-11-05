#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found (macOS is required)" >&2
  exit 1
fi

python3 - <<'PY'
import json
import re
import subprocess
import sys

try:
    output = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
except subprocess.CalledProcessError as error:
    sys.exit(f"error: simctl failed: {error}")

data = json.loads(output)
best = None

for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        key = (version, name)
        if best is None or key > best[0]:
            best = (key, device)

if best is None:
    sys.exit("error: no available iPhone simulator found")

print(f"platform=iOS Simulator,id={best[1]['udid']}")
PY
