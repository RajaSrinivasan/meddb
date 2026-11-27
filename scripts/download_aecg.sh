#!/usr/bin/env bash
# Download the official HL7 2003-12 annotated ECG schema example.
# No public real clinical aECG corpus was available as of 26 Nov 2026.
set -euo pipefail
source "$(dirname "$0")/download_common.sh"

URL="https://raw.githubusercontent.com/FDA/aecg-python/refs/heads/main/src/aecg/data/hl7/2003-12%20Schema/example/Example%20aECG.xml"
fetch "$URL" "$ROOT/data/aecg/Example-aECG.xml"
verify_sums "$ROOT/data/aecg"
echo "aecg sample ok"
