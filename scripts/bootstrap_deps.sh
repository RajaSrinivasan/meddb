#!/usr/bin/env bash
# Build libwfdb 10.7.0 and EDFlib (pinned commit) into /usr/local.
# libhdf5 and libmatio come from the system packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${PREFIX:-/usr/local}"
WORKDIR="${WORKDIR:-/tmp/meddb-deps}"
WFDB_URL="https://github.com/bemoody/wfdb/archive/refs/tags/10.7.0.tar.gz"
EDFLIB_COMMIT="b980627750763448db9511c3ae3e8dfdc1f63d98"
EDFLIB_URL="https://gitlab.com/Teuniz/EDFlib/-/archive/${EDFLIB_COMMIT}/EDFlib-${EDFLIB_COMMIT}.tar.gz"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing command: $1" >&2
    exit 1
  fi
}

need gcc
need curl
need make
need pkg-config

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "need root to install into $PREFIX" >&2
    exit 1
  fi
}

if ! pkg-config --exists hdf5; then
  echo "libhdf5 development files not found (pkg-config hdf5). On Ubuntu: sudo apt-get install libhdf5-dev" >&2
  exit 1
fi
if ! pkg-config --exists matio; then
  echo "libmatio development files not found. On Ubuntu: sudo apt-get install libmatio-dev" >&2
  exit 1
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [[ ! -e "$PREFIX/lib/libwfdb.so" ]]; then
  curl -fsSL -o wfdb-10.7.0.tar.gz "$WFDB_URL"
  tar -xzf wfdb-10.7.0.tar.gz
  (
    cd wfdb-10.7.0
    ./configure --without-netfiles --without-flac --prefix="$PREFIX"
    make -C lib -j"$(nproc)"
    as_root make -C lib install
  )
fi

if [[ ! -e "$PREFIX/lib/libedf.so" ]]; then
  curl -fsSL -o edflib.tar.gz "$EDFLIB_URL"
  tar -xzf edflib.tar.gz
  (
    cd "EDFlib-${EDFLIB_COMMIT}"
    gcc -O2 -fPIC -fvisibility=hidden -D_LARGEFILE64_SOURCE -D_LARGEFILE_SOURCE \
      -DEDFLIB_SO_DLL -DEDFLIB_BUILD -c edflib.c -o edflib.o
    gcc -shared -Wl,-soname,libedf.so.1 -o libedf.so.1.0 edflib.o -lm
    as_root install -d "$PREFIX/lib" "$PREFIX/include"
    as_root install -m 755 libedf.so.1.0 "$PREFIX/lib/libedf.so.1.0"
    as_root ln -sfn libedf.so.1.0 "$PREFIX/lib/libedf.so.1"
    as_root ln -sfn libedf.so.1 "$PREFIX/lib/libedf.so"
    as_root install -m 644 edflib.h "$PREFIX/include/edflib.h"
  )
fi

if command -v ldconfig >/dev/null 2>&1; then
  as_root ldconfig
fi

plotly="$ROOT/julia/vendor/plotly.min.js"
if [[ ! -f "$plotly" ]]; then
  mkdir -p "$(dirname "$plotly")"
  curl -fsSL -o "$plotly" "https://cdn.plot.ly/plotly-2.35.2.min.js"
fi

echo "dependencies ready: libwfdb, libedf, $(pkg-config --modversion hdf5) hdf5, $(pkg-config --modversion matio) matio"
