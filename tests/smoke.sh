#!/usr/bin/env bash
# Build-independent smoke checks. Expects ./bin tools and, when present, data/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/bin/test_common"

run_wfdb() {
  local out
  out="$("$ROOT/bin/meddb-wfdb" "$1" --duration 1)"
  grep -q "fs=$2" <<<"$out"
  grep -q "channels: $3" <<<"$out"
  printf '%s\n' "$out"
}

if [[ -f data/wfdb/mitdb/100.hea ]]; then
  echo "$ROOT/bin/meddb-wfdb data/wfdb/mitdb/100"
  summary="$(run_wfdb data/wfdb/mitdb/100 360 2)"
  ann="$(awk '/^annotations:/{print $2}' <<<"$summary")"
  test "$ann" -gt 0
  grep -q "label=MLII" <<<"$summary"
fi

if [[ -f data/wfdb/ptbxl/00001_hr.hea ]]; then
  run_wfdb data/wfdb/ptbxl/00001_hr 500 12 >/dev/null
fi

if [[ -f data/edf/sleep-edfx/SC4001E0-PSG.edf ]]; then
  out="$("$ROOT/bin/meddb-edf" data/edf/sleep-edfx/SC4001E0-PSG.edf \
    --hypnogram data/edf/sleep-edfx/SC4001EC-Hypnogram.edf --duration 1)"
  grep -q "label=EEG Fpz-Cz" <<<"$out"
fi

if [[ -f data/edf/chbmit/chb01_01.edf ]]; then
  out="$("$ROOT/bin/meddb-edf" data/edf/chbmit/chb01_01.edf --duration 0.05)"
  grep -q "duration_s: 3600" <<<"$out"
fi

if [[ -f data/edf/biosemi/0dfc2c2cf4_eyesclosed.bdf ]]; then
  out="$("$ROOT/bin/meddb-edf" data/edf/biosemi/0dfc2c2cf4_eyesclosed.bdf --duration 0.02)"
  grep -q "format: bdf" <<<"$out"
fi

if [[ -f data/mat/cpsc/A0001.mat ]]; then
  out="$("$ROOT/bin/meddb-mat" data/mat/cpsc/A0001.mat --duration 0.1)"
  grep -q "fs=500" <<<"$out"
fi

if [[ -f data/mat/ptbxl/HR00001.mat ]]; then
  out="$("$ROOT/bin/meddb-mat" data/mat/ptbxl/HR00001.mat --duration 0.1)"
  grep -q "channels: 12" <<<"$out"
fi

if [[ -f data/hdf5/heartcycle/CH07_59146237_s0000029.h5 ]]; then
  out="$("$ROOT/bin/meddb-hdf5" data/hdf5/heartcycle/CH07_59146237_s0000029.h5 --duration 0.2)"
  grep -q "layout: HeartCycle" <<<"$out"
fi

if [[ -f data/hdf5/but-cgm/124001_2124-04-05_ECG.h5 ]]; then
  out="$("$ROOT/bin/meddb-hdf5" data/hdf5/but-cgm/124001_2124-04-05_ECG.h5 --duration 0.02)"
  grep -q "fs=1000" <<<"$out"
fi

echo "smoke checks passed"
