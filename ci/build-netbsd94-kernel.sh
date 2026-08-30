#!/bin/sh
# NetBSD 9.4/amd64 の GENERIC カーネルを Linux の上で cross build する。
#
#   sh ci/build-netbsd94-kernel.sh [<当て物> ...]
#
# NetBSD の build.sh は host が Linux でも通る。tools を先に組んでから
# kernel を組む。出来上がりは $OUT/netbsd-GENERIC.gz。
#
# 何のために組むか:
#
#   Vultr は virtio を modern (1.0) だけで見せる。NetBSD 9 の virtio_pci.c は
#   device id を 0x1000-0x103F しか見ず VIRTIO_F_VERSION_1 も知らないので、
#   ディスクが一つも生えず root device のプロンプトで止まる。10 で入った
#   modern transport を 9.4 へ backport したカーネルが要る。
#
#   NetBSD 10 の virtio を丸ごと持ってくると子の API まで変わり、
#   if_vioif.c だけで 3171 行の差になる。触るのは PCI 層だけにする。

set -eu

REL=${REL:-9.4}
ARCH=${ARCH:-amd64}
BASE=${BASE:-$(pwd)}
WRK=${WRK:-$BASE/wrk-netbsd$REL}
OUT=${OUT:-$BASE/out}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}
MIRROR=${MIRROR:-http://cdn.netbsd.org/pub/NetBSD/NetBSD-$REL/source/sets}

mkdir -p "$WRK" "$OUT"
cd "$WRK"

# src と syssrc の二つで足りる。gnusrc や sharesrc は kernel には要らないが、
# build.sh tools が share/mk を読むので src は要る。
for s in src syssrc; do
	if [ ! -s $s.tgz ]; then
		echo "--- $s.tgz を取る ---"
		curl -fsSL -o $s.tgz "$MIRROR/$s.tgz"
	fi
done
if [ ! -d usr/src ]; then
	echo "--- 展開 ---"
	mkdir -p usr
	for s in src syssrc; do tar xzf $s.tgz -C usr 2>/dev/null || tar xzf $s.tgz; done
fi
SRC=$WRK/usr/src
[ -d "$SRC" ] || { echo "$0: usr/src が無い"; exit 1; }

# 当て物。引数で渡されたものを順に当てる。当たらなければ止める。
for p in "$@"; do
	echo "--- 当てる: $p ---"
	(cd "$SRC" && patch -p0 --batch < "$p")
done

cd "$SRC"
echo "--- build.sh tools ($JOBS 並列) ---"
./build.sh -m "$ARCH" -U -j "$JOBS" -O "$WRK/obj" -T "$WRK/tools" -D "$WRK/dest" \
	-R "$WRK/rel" tools
echo "--- build.sh kernel=GENERIC ---"
./build.sh -m "$ARCH" -U -j "$JOBS" -O "$WRK/obj" -T "$WRK/tools" -D "$WRK/dest" \
	-R "$WRK/rel" kernel=GENERIC

K=$(find "$WRK/obj" -name netbsd -type f -path '*GENERIC*' | head -1)
[ -n "$K" ] || { echo "$0: netbsd が出来ていない"; exit 1; }
ls -l "$K"
gzip -9 -c "$K" > "$OUT/netbsd-GENERIC.gz"
ls -l "$OUT/netbsd-GENERIC.gz"
echo "OK: $OUT/netbsd-GENERIC.gz"
