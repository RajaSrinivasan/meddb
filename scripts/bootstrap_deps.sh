#!/usr/bin/env bash
# Build libwfdb 10.7.0 and EDFlib (pinned commit) into /usr/local.
# libhdf5, libmatio, and libbiosig come from the system packages.
# Ubuntu 24.04 ships libbiosig 3.0.2 as libbiosig-dev (package version 2.6.0).
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

install_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "need apt-get to install: $*" >&2
    exit 1
  fi
  as_root apt-get update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# libbiosig's .pc file advertises broken -D= macros; --exists is still valid.
# Do not pass `pkg-config --cflags libbiosig` to the compiler.
if ! pkg-config --exists libbiosig || [[ ! -f /usr/include/biosig.h && ! -f /usr/local/include/biosig.h ]]; then
  echo "installing libbiosig-dev"
  install_apt libbiosig-dev
fi
if ! pkg-config --exists libxml-2.0; then
  echo "installing libxml2-dev"
  install_apt libxml2-dev
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

echo "dependencies ready: libwfdb, libedf, libbiosig $(pkg-config --modversion libbiosig), $(pkg-config --modversion hdf5) hdf5, $(pkg-config --modversion matio) matio"
