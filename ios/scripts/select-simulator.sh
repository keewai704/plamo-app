#!/usr/bin/env bash
# Prints an xcodebuild destination for the newest available simulator.
#   usage: select-simulator.sh iPhone|iPad
set -euo pipefail

python3 - "${1:-iPhone}" <<'PY'
import json
import re
import subprocess
import sys

family = sys.argv[1]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))

best = None
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        if device.get("name", "").startswith(family):
            key = (version, device["name"])
            if best is None or key > best[0]:
                best = (key, device)

if best is None:
    sys.exit(f"error: no available {family} simulator found")

print(f"platform=iOS Simulator,id={best[1]['udid']}")
PY
