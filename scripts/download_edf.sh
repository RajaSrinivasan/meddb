#!/usr/bin/env bash
# Download Sleep-EDF, CHB-MIT, and the Biosemi-Muse BDF sample into data/edf/.
# --quick skips the larger CHB-MIT and BDF files.
set -euo pipefail
source "$(dirname "$0")/download_common.sh"

quick=0
for arg in "$@"; do
  case "$arg" in
    --quick) quick=1 ;;
    -h|--help)
      echo "usage: $0 [--quick]"
      exit 0
      ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

fetch "https://physionet.org/files/sleep-edfx/1.0.0/sleep-cassette/SC4001E0-PSG.edf" \
  "$ROOT/data/edf/sleep-edfx/SC4001E0-PSG.edf"
fetch "https://physionet.org/files/sleep-edfx/1.0.0/sleep-cassette/SC4001EC-Hypnogram.edf" \
  "$ROOT/data/edf/sleep-edfx/SC4001EC-Hypnogram.edf"

if [[ "$quick" -eq 0 ]]; then
  fetch "https://physionet.org/files/chbmit/1.0.0/chb01/chb01_01.edf" \
    "$ROOT/data/edf/chbmit/chb01_01.edf"
  fetch "https://osf.io/download/69681bf80d1b3b98bf563523/" \
    "$ROOT/data/edf/biosemi/0dfc2c2cf4_eyesclosed.bdf"
fi

if [[ "$quick" -eq 1 ]]; then
  (cd "$ROOT/data/edf" && sha256sum -c <(grep -E 'sleep-edfx/' SHA256SUMS))
else
  verify_sums "$ROOT/data/edf"
fi
echo "edf samples ok"
