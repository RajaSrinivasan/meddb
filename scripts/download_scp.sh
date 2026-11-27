#!/usr/bin/env bash
# Download the OpenECG Hannover SCP-ECG records and the WFDB test.scp fixture.
# The OpenECG zip holds the same 12 clinical records twice: redundancy-reduced
# (readable by libbiosig) and high-compression (not decoded by libbiosig 3.0.2).
set -euo pipefail
source "$(dirname "$0")/download_common.sh"

OPENECG_URL="https://web.archive.org/web/20060216180358/http://www.openecg.net/ECGsamples.zip"
WFDB_SCP_URL="https://physionet.org/files/wfdb/10.7.0/checkpkg/input/test.scp"
cache="$ROOT/data/scp/.cache"
redred="$ROOT/data/scp/hannover"
high="$ROOT/data/scp/hannover-high"

mkdir -p "$cache" "$redred" "$high"
fetch "$OPENECG_URL" "$cache/ECGsamples.zip"

if [[ ! -f "$redred/PFE105.scp" || ! -f "$high/PFE105.scp" ]]; then
  if ! unzip -t "$cache/ECGsamples.zip" >/dev/null; then
    echo "ECGsamples.zip is not a zip archive" >&2
    exit 1
  fi
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  unzip -q -o "$cache/ECGsamples.zip" -d "$tmp"
  unzip -q -o "$tmp/scp_redred.zip" -d "$redred"
  unzip -q -o "$tmp/scp_high.zip" -d "$high"
  rm -rf "$tmp"
  trap - EXIT
fi

fetch "$WFDB_SCP_URL" "$ROOT/data/scp/test.scp"
verify_sums "$ROOT/data/scp"
echo "scp samples ok"
