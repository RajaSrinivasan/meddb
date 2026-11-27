#!/usr/bin/env bash
# Shared helpers for scripts/download_*.sh. Source this file; do not execute it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEDDB_UA="${MEDDB_UA:-meddb/0.1 (research; +https://github.com/RajaSrinivasan/meddb)}"

fetch() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    echo "have ${dest#"$ROOT"/}"
    return 0
  fi
  echo "get $url"
  curl -fL --retry 4 --retry-delay 2 -A "$MEDDB_UA" -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
}

verify_sums() {
  local dir="$1"
  if [[ ! -f "$dir/SHA256SUMS" ]]; then
    echo "missing $dir/SHA256SUMS" >&2
    exit 1
  fi
  (cd "$dir" && sha256sum -c SHA256SUMS)
}
