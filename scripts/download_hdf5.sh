#!/usr/bin/env bash
# Download HeartCycle and BUT CGM HDF5 samples into data/hdf5/.
# --quick skips the 24-hour BUT CGM recording.
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

fetch "https://physionet.org/files/heartcycle/1.0.0/59146237/measure/CH07_59146237_s0000029.h5" \
  "$ROOT/data/hdf5/heartcycle/CH07_59146237_s0000029.h5"
if [[ "$quick" -eq 0 ]]; then
  fetch "https://physionet.org/files/but-cgm/1.0.0/124001/124001_2124-04-05_ECG.h5" \
    "$ROOT/data/hdf5/but-cgm/124001_2124-04-05_ECG.h5"
  verify_sums "$ROOT/data/hdf5"
else
  (cd "$ROOT/data/hdf5" && sha256sum -c <(grep heartcycle SHA256SUMS))
fi
echo "hdf5 samples ok"
