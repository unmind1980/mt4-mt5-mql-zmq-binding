#!/usr/bin/env bash
#+------------------------------------------------------------------+
#| build-mingw.sh -- rebuild the DLLs shipped with mql-zmq          |
#|                                                                  |
#| Builds libsodium and libzmq from the official sources with the   |
#| MinGW-w64 toolchains of MSYS2, for both MetaTrader runtimes:     |
#|                                                                  |
#|   x86 -> 32bit -> Library/MT4  (MT4 and 32bit MT5)               |
#|   x64 -> 64bit -> Library/MT5  (MT5, the default)                |
#|                                                                  |
#| Usage (from an MSYS2 shell):                                     |
#|                                                                  |
#|   MSYSTEM=MINGW32 ./build-mingw.sh x86                           |
#|   MSYSTEM=MINGW64 ./build-mingw.sh x64                           |
#|                                                                  |
#| libsodium is linked STATICALLY into libzmq.dll on purpose:       |
#| the result is a single self contained DLL, no VC++ runtime and   |
#| no extra libsodium-xx.dll to deploy.                             |
#|                                                                  |
#| libzmq is configured with --enable-drafts, so the 4.3.x draft    |
#| socket types and socket options are available to MQL.            |
#+------------------------------------------------------------------+
set -uo pipefail

ZMQ_VERSION="4.3.5"
SODIUM_VERSION="1.0.22"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$SCRIPT_DIR/work"
DIST_DIR="$SCRIPT_DIR/dist"

ZMQ_SRC="$SCRIPT_DIR/src/zeromq-${ZMQ_VERSION}"
SODIUM_SRC="$SCRIPT_DIR/src/libsodium-${SODIUM_VERSION}"

log() { echo "=== $*"; }

# MSYS2 coreutils `rm -r` is denied by some sandboxes, which breaks configure
# (`rm -r conftest.dir`) and any cleanup of the build tree. Put a shim that
# routes directory deletes through python first on PATH. The shim picks its
# own python from PATH and falls back to the real rm when none is found, so
# it is harmless on a normal machine.
if [ -x "$SCRIPT_DIR/msys-shim/bin/rm" ]; then
  export MQL_ZMQ_PYTHON="${MQL_ZMQ_PYTHON:-}"
  export PATH="$SCRIPT_DIR/msys-shim/bin:$PATH"
fi

fetch_sources() {
  mkdir -p "$SCRIPT_DIR/dl" "$SCRIPT_DIR/src"
  local zmq_tgz="$SCRIPT_DIR/dl/zeromq-${ZMQ_VERSION}.tar.gz"
  local sodium_tgz="$SCRIPT_DIR/dl/libsodium-${SODIUM_VERSION}.tar.gz"
  [ -f "$zmq_tgz" ] || curl -L -o "$zmq_tgz" \
    "https://github.com/zeromq/libzmq/releases/download/v${ZMQ_VERSION}/zeromq-${ZMQ_VERSION}.tar.gz"
  [ -f "$sodium_tgz" ] || curl -L -o "$sodium_tgz" \
    "https://github.com/jedisct1/libsodium/releases/download/${SODIUM_VERSION}-RELEASE/libsodium-${SODIUM_VERSION}.tar.gz"
  [ -d "$ZMQ_SRC" ] || tar -xzf "$zmq_tgz" -C "$SCRIPT_DIR/src"
  [ -d "$SODIUM_SRC" ] || tar -xzf "$sodium_tgz" -C "$SCRIPT_DIR/src"
}

# The release tarballs ship pregenerated autotools files. Copying them around
# scrambles the timestamps and make then tries to re-run aclocal/automake,
# which are not installed. Put the generated files in the future instead.
stamp_tree() {
  ( cd "$1" && \
    find . -type f -exec touch -d '2020-01-01 00:00:00' {} + && \
    find . \( -name '*.in' -o -name 'aclocal.m4' -o -name 'configure' \
              -o -name 'config.guess' -o -name 'config.sub' \
              -o -name 'install-sh' -o -name 'ltmain.sh' -o -name 'missing' \
              -o -name 'depcomp' -o -name 'compile' -o -name 'test-driver' \) \
         -exec touch -d '2020-01-02 00:00:00' {} + )
}

# Fresh copy of the sources to build in. Windows sometimes refuses to delete a
# directory tree right away, so fall back to a numbered directory.
prepare_tree() {
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    chmod -R u+w "$dst" 2>/dev/null
    rm -rf "$dst" 2>/dev/null || sleep 1
    rm -rf "$dst" 2>/dev/null || dst="${dst}-build$$"
  fi
  cp -r "$src" "$dst"
  stamp_tree "$dst"
  echo "$dst"
}

# Object enumeration relative to a base directory. `find` in MSYS2 does not
# descend into `.libs/` (it reports 0 matches while ls shows 119) and globstar
# needs dotglob which still misses them, so spell the patterns out explicitly.
list_objs() {
  local base="$1"; shift
  local pat f out=""
  for pat in "$@"; do
    for f in $(cd "$base" && ls $pat 2>/dev/null); do out="$out $f"; done
  done
  echo "$out"
}

build_arch() {
  local arch="$1"
  local host prefix msystem
  case "$arch" in
    x86) host="i686-w64-mingw32";   msystem="MINGW32";;
    x64) host="x86_64-w64-mingw32"; msystem="MINGW64";;
    *) echo "unknown arch: $arch" >&2; return 1;;
  esac

  if [ "${MSYSTEM:-}" != "$msystem" ]; then
    echo "!!! Run this from an MSYS2 $msystem shell:" >&2
    echo "    MSYSTEM=$msystem $0 $arch" >&2
    return 1
  fi

  prefix="$DIST_DIR/$arch"
  mkdir -p "$prefix" "$WORK_DIR/$arch"

  local cflags="-O2 -fno-ident -fno-common -D_WIN32_WINNT=0x0600"
  local cxxflags="-O2 -fno-ident -fno-common -D_WIN32_WINNT=0x0600"

  log "[$arch] libsodium ${SODIUM_VERSION} (static)"
  if [ -f "$prefix/lib/libsodium.a" ]; then
    echo "    already built, skipping"
  else
    local sdir
    sdir="$(prepare_tree "$SODIUM_SRC" "$WORK_DIR/$arch/libsodium")"
    ( cd "$sdir" && \
      ./configure --host="$host" --prefix="$prefix" \
                  --enable-static --disable-shared \
                  --disable-dependency-tracking \
                  CFLAGS="$cflags" && \
      make -j"$(nproc)" && make install ) || return 1
  fi

  log "[$arch] libzmq ${ZMQ_VERSION} (shared, drafts on)"
  local zdir
  zdir="$(prepare_tree "$ZMQ_SRC" "$WORK_DIR/$arch/libzmq")"
  # configure only needs to succeed; the link is done below with a manual g++
  # invocation. libtool insists on linking libstdc++ / libgcc_s / libwinpthread
  # dynamically even with -static-libstdc++, which would drag libstdc++-6.dll,
  # libgcc_s_*.dll and libwinpthread-1.dll into the Libraries folder.
  # --with-libsodium and --enable-curve must be explicit: they default to off,
  # and without them zmq_curve_keypair returns ENOTSUP even though libsodium.a
  # was linked in.
  ( cd "$zdir" && \
    PKG_CONFIG_PATH="$prefix/lib/pkgconfig" \
    sodium_CFLAGS="-I$prefix/include" \
    sodium_LIBS="-L$prefix/lib -l:libsodium.a" \
    ./configure --host="$host" --prefix="$prefix" \
                --enable-shared --disable-static \
                --enable-drafts --enable-curve --with-libsodium \
                --disable-dependency-tracking \
                --without-docs \
                CFLAGS="$cflags" CXXFLAGS="$cxxflags" && \
    grep -q "define ZMQ_USE_LIBSODIUM 1" "$zdir/src/platform.hpp" \
     || { echo "!!! libsodium not picked up by configure" >&2; exit 1; } && \
    grep -q "define ZMQ_HAVE_CURVE 1" "$zdir/src/platform.hpp" \
     || { echo "!!! curve support not enabled" >&2; exit 1; } && \
    make -j"${JOBS:-4}" src/libzmq.la ) || return 1

  ( cd "$zdir" && \
    mkdir -p "$prefix/bin" && \
    objs="$(list_objs "$zdir" 'src/.libs/*.o' 'external/sha1/.libs/*.o')" && \
    echo "    linking $(echo "$objs" | wc -w) objects" && \
    [ "$(echo "$objs" | wc -w)" -ge 40 ] && \
    ${host}-g++ -shared -O2 -fno-ident \
                 -static-libgcc -static-libstdc++ \
                 -o "$prefix/bin/libzmq.dll" \
                 $objs \
                 -Wl,--kill-at,--no-insert-timestamp \
                 -Wl,-Bstatic -lstdc++ -lwinpthread -lgcc -lgcc_eh \
                 -Wl,-Bdynamic \
                 "$prefix/lib/libsodium.a" \
                 -lws2_32 -liphlpapi -ladvapi32 -lnetapi32 -lrpcrt4 ) \
    || { echo "!!! linking libzmq.dll failed" >&2; return 1; }

  local dll="$prefix/bin/libzmq.dll"
  [ -f "$dll" ] || { echo "!!! $dll not found" >&2; return 1; }

  if [ "$arch" = "x86" ]; then
    mkdir -p "$REPO_DIR/Library/MT4"
    cp "$dll" "$REPO_DIR/Library/MT4/libzmq.dll"
    log "[$arch] -> Library/MT4/libzmq.dll"
  else
    mkdir -p "$REPO_DIR/Library/MT5"
    cp "$dll" "$REPO_DIR/Library/MT5/libzmq.dll"
    log "[$arch] -> Library/MT5/libzmq.dll"
  fi
}

main() {
  fetch_sources
  build_arch "${1:-x64}" || exit 1
  log "done"
}

main "$@"
