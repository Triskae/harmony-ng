#!/bin/sh
# BearSSL sources at the pinned commit in build/tmp/bearssl (or BEARSSL_DIR), copied from the copy
# kept in the repository (build/vendor/bearssl, see build/vendor/README.md): no network.
# BEARSSL_FETCH=1 clones BEARSSL_URL instead, to compare it with the vendored copy or to update it.
#
# The commit is part of the ABI: BearSSL contexts are structs the caller allocates, so plugins
# linked against payload/lib/libbearssl.so.0 only work with the same commit. A new commit needs
# a new SONAME (libbearssl.so.1) in build/compile_all.sh, a new vendored copy and BEARSSL_TREE
# below, and a plugin rebuild.
#
# The prepared folder holds .bearssl_commit with the commit; the builds key their caches on it
# (it is not a git checkout, and git -C there would answer with the harmony-ng commit).
set -eu

BEARSSL_COMMIT="7bea48e5e850ab4cafbe68d3765cdaba13a86d6f"
# git tree of that commit: build/vendor/bearssl must have exactly this tree (tests/test_build_downloads.sh)
# shellcheck disable=SC2034
BEARSSL_TREE="a8f933a27b14eaf3a348fe9b294bf4262dbb216c"
BEARSSL_URL="${BEARSSL_URL:-https://bearssl.org/git/BearSSL}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BEARSSL_DIR="${BEARSSL_DIR:-$SCRIPT_DIR/tmp/bearssl}"
BEARSSL_VENDOR="$SCRIPT_DIR/vendor/bearssl"
STAMP=".bearssl_commit"

if [ "$(cat "$BEARSSL_DIR/$STAMP" 2>/dev/null)" = "$BEARSSL_COMMIT" ]; then
    exit 0
fi
# a clone made by an earlier version of this script, or by BEARSSL_FETCH=1
if [ -d "$BEARSSL_DIR/.git" ]; then
    if [ "$(git -C "$BEARSSL_DIR" rev-parse HEAD 2>/dev/null)" != "$BEARSSL_COMMIT" ]; then
        if ! git -C "$BEARSSL_DIR" cat-file -e "$BEARSSL_COMMIT^{commit}" 2>/dev/null; then
            echo "[!] $BEARSSL_DIR is a clone without BearSSL $BEARSSL_COMMIT; remove it and run again" >&2
            exit 1
        fi
        git -C "$BEARSSL_DIR" checkout -q "$BEARSSL_COMMIT"
        rm -f "$BEARSSL_DIR"/libbearssl*.a "$BEARSSL_DIR"/libbearssl.flags
    fi
    echo "$BEARSSL_COMMIT" > "$BEARSSL_DIR/$STAMP"
    exit 0
fi
if [ -e "$BEARSSL_DIR" ]; then
    echo "[!] $BEARSSL_DIR exists but is not BearSSL at $BEARSSL_COMMIT; remove it and run again" >&2
    exit 1
fi

mkdir -p "$(dirname "$BEARSSL_DIR")"
TMP_DIR="$BEARSSL_DIR.tmp.$$"
rm -rf "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT
if [ "${BEARSSL_FETCH:-0}" = "1" ]; then
    echo "[-] Fetching BearSSL $BEARSSL_COMMIT from $BEARSSL_URL (BEARSSL_FETCH=1)..."
    git clone -q "$BEARSSL_URL" "$TMP_DIR"
    git -C "$TMP_DIR" checkout -q "$BEARSSL_COMMIT"
else
    if [ ! -f "$BEARSSL_VENDOR/inc/bearssl.h" ]; then
        echo "[!] $BEARSSL_VENDOR is missing (build/vendor/README.md); BEARSSL_FETCH=1 clones it instead" >&2
        exit 1
    fi
    cp -R "$BEARSSL_VENDOR" "$TMP_DIR"
fi
# the stamp last: a cut copy is never taken for a complete one
echo "$BEARSSL_COMMIT" > "$TMP_DIR/$STAMP"
mv "$TMP_DIR" "$BEARSSL_DIR"
trap - EXIT
