#!/usr/bin/env bash
# Download the pinned MIT-BIH and PTB-XL WFDB samples into data/wfdb/.
set -euo pipefail
source "$(dirname "$0")/download_common.sh"

fetch "https://physionet.org/files/mitdb/1.0.0/100.hea" "$ROOT/data/wfdb/mitdb/100.hea"
fetch "https://physionet.org/files/mitdb/1.0.0/100.dat" "$ROOT/data/wfdb/mitdb/100.dat"
fetch "https://physionet.org/files/mitdb/1.0.0/100.atr" "$ROOT/data/wfdb/mitdb/100.atr"
fetch "https://physionet.org/files/ptb-xl/1.0.3/records500/00000/00001_hr.hea" \
  "$ROOT/data/wfdb/ptbxl/00001_hr.hea"
fetch "https://physionet.org/files/ptb-xl/1.0.3/records500/00000/00001_hr.dat" \
  "$ROOT/data/wfdb/ptbxl/00001_hr.dat"
verify_sums "$ROOT/data/wfdb"
echo "wfdb samples ok"
