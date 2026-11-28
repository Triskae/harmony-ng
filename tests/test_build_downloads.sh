#!/bin/sh
# Build downloads are checked against a SHA-256 before use.
# build/build_busybox.sh runs from a scratch copy of the repository layout with a fake curl
# first in PATH (no network): a download that does not match, or an HTTP error page saved by
# an earlier run, must stop the build and leave no tarball under the final name. The CI and
# release workflows must check every Bootlin toolchain tarball with sha256sum. BearSSL is prepared
# from build/vendor/bearssl with no network, and that copy is the pinned upstream tree.
set -eu
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/repo/build" "$WORK/bin"
cp "$REPO_ROOT/build/build_busybox.sh" "$WORK/repo/build/"
cat > "$WORK/bin/curl" <<'FAKE'
#!/bin/sh
echo "curl $*" >> "$FAKE_LOG"
while [ $# -gt 0 ]; do case "$1" in -o) shift; out=$1 ;; esac; shift; done
printf '<html>404 Not Found</html>\n' > "$out"
exit 0
FAKE
chmod +x "$WORK/bin/curl"
TAR="$WORK/repo/build/tmp/busybox-1.36.1.tar.bz2"

# 1. A download that does not match its SHA-256
if PATH="$WORK/bin:$PATH" FAKE_LOG="$WORK/log" bash "$WORK/repo/build/build_busybox.sh" mips >"$WORK/out" 2>&1; then
    echo "FAIL: a download with the wrong SHA-256 did not stop the build"; exit 1
fi
[ ! -e "$TAR" ] || { echo "FAIL: the bad download was kept as $TAR"; exit 1; }
grep -q 'SHA-256' "$WORK/out" || { echo "FAIL: no word about the checksum"; cat "$WORK/out"; exit 1; }

# 2. An error page cached by an earlier run is not used: it is fetched again (and refused)
printf '<html>error</html>\n' > "$TAR"
: > "$WORK/log"
if PATH="$WORK/bin:$PATH" FAKE_LOG="$WORK/log" bash "$WORK/repo/build/build_busybox.sh" mips >"$WORK/out" 2>&1; then
    echo "FAIL: a cached file with the wrong SHA-256 was used"; exit 1
fi
grep -q '^curl ' "$WORK/log" || { echo "FAIL: the bad cached file was not fetched again"; exit 1; }
[ ! -e "$TAR" ] || { echo "FAIL: the bad cached file is still there"; exit 1; }

# 3. Every Bootlin download in the workflows is checked
for wf in "$REPO_ROOT/.github/workflows/ci.yml" "$REPO_ROOT/.github/workflows/release.yml"; do
    n_dl=$(grep -c 'toolchains.bootlin.com' "$wf")
    n_ck=$(grep -c 'toolchain.tar.bz2" | sha256sum -c -' "$wf")
    [ "$n_dl" -gt 0 ] && [ "$n_dl" = "$n_ck" ] || { echo "FAIL: $wf: $n_dl toolchain downloads, $n_ck checked"; exit 1; }
    if grep -q 'curl -sSL "https://toolchains.bootlin.com[^"]*" | tar' "$wf"; then
        echo "FAIL: $wf still pipes an unchecked toolchain download into tar"; exit 1
    fi
done

# 4. BearSSL comes from the vendored copy: no git, no curl (both fail and log if called)
mkdir -p "$WORK/nonet"
for tool in git curl wget; do
    printf '#!/bin/sh\necho "%s $*" >> "$NONET_LOG"\nexit 1\n' "$tool" > "$WORK/nonet/$tool"
    chmod +x "$WORK/nonet/$tool"
done
: > "$WORK/nonet.log"
BEARSSL_COMMIT=$(sed -n 's/^BEARSSL_COMMIT="\([0-9a-f]*\)"$/\1/p' "$REPO_ROOT/build/fetch_bearssl.sh")
for run in 1 2; do
    PATH="$WORK/nonet:$PATH" NONET_LOG="$WORK/nonet.log" BEARSSL_DIR="$WORK/bearssl" \
        sh "$REPO_ROOT/build/fetch_bearssl.sh" >"$WORK/out" 2>&1 \
        || { echo "FAIL: fetch_bearssl.sh run $run without network"; cat "$WORK/out"; exit 1; }
done
[ ! -s "$WORK/nonet.log" ] || { echo "FAIL: fetch_bearssl.sh reached for the network:"; cat "$WORK/nonet.log"; exit 1; }
[ -f "$WORK/bearssl/inc/bearssl.h" ] || { echo "FAIL: no BearSSL sources in BEARSSL_DIR"; exit 1; }
[ "$(cat "$WORK/bearssl/.bearssl_commit")" = "$BEARSSL_COMMIT" ] || { echo "FAIL: wrong .bearssl_commit"; exit 1; }
# without the vendored copy it stops, and still does not download
mkdir -p "$WORK/novendor/build"
cp "$REPO_ROOT/build/fetch_bearssl.sh" "$WORK/novendor/build/"
if PATH="$WORK/nonet:$PATH" NONET_LOG="$WORK/nonet.log" sh "$WORK/novendor/build/fetch_bearssl.sh" >"$WORK/out" 2>&1; then
    echo "FAIL: fetch_bearssl.sh without build/vendor/bearssl did not stop"; exit 1
fi
grep -q 'BEARSSL_FETCH=1' "$WORK/out" || { echo "FAIL: no word about BEARSSL_FETCH"; cat "$WORK/out"; exit 1; }
[ ! -s "$WORK/nonet.log" ] || { echo "FAIL: fetch_bearssl.sh downloaded without BEARSSL_FETCH=1"; exit 1; }

# 5. build/vendor/bearssl is the upstream tree of the pinned commit, byte for byte
BEARSSL_TREE=$(sed -n 's/^BEARSSL_TREE="\([0-9a-f]*\)"$/\1/p' "$REPO_ROOT/build/fetch_bearssl.sh")
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tree=$(cd "$REPO_ROOT" && GIT_INDEX_FILE="$WORK/vendor.index" git add -f build/vendor/bearssl \
        && GIT_INDEX_FILE="$WORK/vendor.index" git write-tree --prefix=build/vendor/bearssl/)
    [ "$tree" = "$BEARSSL_TREE" ] || { echo "FAIL: build/vendor/bearssl has tree $tree, not $BEARSSL_TREE (BearSSL $BEARSSL_COMMIT)"; exit 1; }
else
    echo "[*] not a git checkout: vendored BearSSL tree not checked"
fi

echo "PASS: build downloads are checked against their SHA-256, BearSSL builds without network"
