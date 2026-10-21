#!/usr/bin/env bash
# Build PHP 8.4.26 and 8.4.27 with AddressSanitizer + debug for the A/B lab.
#
# Run inside WSL2/Linux. Needs: gcc, make, autoconf, bison, pkg-config and
# libxml2 headers (re2c is NOT needed for release tarballs; generated parsers
# are shipped). Debian/Kali:  sudo apt install build-essential autoconf bison \
#   pkg-config libxml2-dev ca-certificates curl
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/builds}"
JOBS="${JOBS:-$(nproc)}"
mkdir -p "$BUILD"

SHA_8426="c248abaebc4bb777b80968f0760da0da8e989836e896c9ff637b6775d7d37662"
SHA_8427="5bafed9994c1a49796b25b5f61c22c9183bfe046b6acc7b363842d03c77f972f"

for v in 8.4.26 8.4.27; do
  case "$v" in
    8.4.26) sha="$SHA_8426" ;;
    8.4.27) sha="$SHA_8427" ;;
  esac
  tarball="$BUILD/php-$v.tar.gz"
  if [ ! -f "$tarball" ]; then
    echo "[*] downloading php-$v.tar.gz"
    curl -fsSL -o "$tarball" "https://www.php.net/distributions/php-$v.tar.gz"
  fi
  echo "$sha  $tarball" | sha256sum -c -
  if [ -x "$BUILD/p$v/bin/php" ]; then
    echo "[=] $BUILD/p$v already built, skipping"
    continue
  fi
  echo "[*] building $v with ASAN (-j$JOBS)"
  rm -rf "$BUILD/php-$v"
  tar -C "$BUILD" -xf "$tarball"
  (
    cd "$BUILD/php-$v"
    CFLAGS="-O1 -g -fsanitize=address -fno-omit-frame-pointer" \
    LDFLAGS="-fsanitize=address" \
    ./configure --prefix="$BUILD/p$v" --disable-all --enable-cli \
      --enable-session --enable-filter --enable-ctype --enable-debug \
      --without-pear >configure.log 2>&1
    make -j"$JOBS" >make.log 2>&1
    make install >install.log 2>&1
  )
  "$BUILD/p$v/bin/php" -v | head -1
done

echo "[+] done. binaries:"
ls -1 "$BUILD"/p8.4.2*/bin/php
