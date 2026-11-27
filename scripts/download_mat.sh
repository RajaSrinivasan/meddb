#!/usr/bin/env bash
# Download PhysioNet Challenge 2021 MATLAB samples and their .hea headers.
set -euo pipefail
source "$(dirname "$0")/download_common.sh"

fetch "https://physionet.org/files/challenge-2021/1.0.3/training/cpsc_2018/g1/A0001.mat" \
  "$ROOT/data/mat/cpsc/A0001.mat"
fetch "https://physionet.org/files/challenge-2021/1.0.3/training/cpsc_2018/g1/A0001.hea" \
  "$ROOT/data/mat/cpsc/A0001.hea"
fetch "https://physionet.org/files/challenge-2021/1.0.3/training/ptb-xl/g1/HR00001.mat" \
  "$ROOT/data/mat/ptbxl/HR00001.mat"
fetch "https://physionet.org/files/challenge-2021/1.0.3/training/ptb-xl/g1/HR00001.hea" \
  "$ROOT/data/mat/ptbxl/HR00001.hea"
verify_sums "$ROOT/data/mat"
echo "mat samples ok"
