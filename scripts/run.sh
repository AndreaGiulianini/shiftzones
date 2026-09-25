#!/usr/bin/env bash
# Rebuilds, quits the running instance and reopens ShiftZones.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
pkill -x ShiftZones 2>/dev/null && sleep 0.5 || true
open build/ShiftZones.app --args "$@"
