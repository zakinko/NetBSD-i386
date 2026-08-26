#!/bin/sh
#
# mozc 3.33.6089 を gyp で建てる。i386 で通るかを見るのが主目的。
#
#	sh ci/netbsd-mozc333.sh [イメージ名] [EMACS_TYPE]
#	例: sh ci/netbsd-mozc333.sh i386-11.0 emacs30nox
#
# 3.33.6089 は gyp を積んだ最後の mozc である。次の 3.33.6133 で
# src/build_mozc.py と src/gyp/ が消える。amd64 では techne で三本とも
# 建つことを確かめた (doc/mozc-333.md)。
#
# i386 が本題である。bazel は singlejar の
#
#	#error This code for 64 bit Unix.
#
# で 32bit を拒むので、pkgsrc も FreeBSD ports も OpenBSD ports も揃って
# i386 を除外している。いま i386 の箱に届く mozc は 2.26 止まりで、
# **3.x を載せる道は gyp しかない。** 通れば 3.33 が i386 に載る。
#
# 測るのは三つ。
#
#   1. gyp の configure が i386 で通ること (target_platform=NetBSD)
#   2. mozc_server と mozc_emacs_helper が建ち、32bit の ELF であること
#   3. 実際に日本語が打てること
#
# ci/netbsd-mozc226.sh と同じ作り。イメージは netbsd-ci-images の release
# から落とし、起動と停止はあちらのスクリプトをそのまま使う。

set -eu

NAME=${1:-i386-11.0}
ETYPE=${2:-emacs30nox}
IMGREPO=${IMGREPO:-zakinko/netbsd-ci-images}
IMGTAG=${IMGTAG:-images}
IMGREF=${IMGREF:-main}
PORT=${PORT:-2333}
WORK=${WORK:-$PWD/.vm-mozc333}
OVERLAY=${OVERLAY:-https://codeload.github.com/zakinko/pkgsrc-zakinko/tar.gz/refs/heads/main}

mkdir -p "$WORK"
cd "$WORK"

echo "=== $NAME を用意する (EMACS_TYPE=$ETYPE) ==="
RAW=https://raw.githubusercontent.com/$IMGREPO/$IMGREF
for f in runvm.sh stopvm.sh; do
	[ -s "$f" ] || curl -fsSL -o "$f" "$RAW/$f"
done
REL=https://github.com/$IMGREPO/releases/download/$IMGTAG
for f in $NAME.qcow2 $NAME.qemu; do
	[ -s "$f" ] || { echo "--- $f を落とす ---"; curl -fsSL -o "$f" "$REL/$f"; }
done

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
     -o BatchMode=yes -o LogLevel=ERROR -o ServerAliveInterval=60 \
     -o ServerAliveCountMax=120 -i $WORK/$NAME.id -p $PORT root@127.0.0.1"

cleanup() {
	rc=$?
	DIR=. sh stopvm.sh "$NAME" > /dev/null 2>&1 || true
	exit $rc
}

echo "=== 起動 ==="
# mozc は protobuf と abseil を丸ごと組むので広く取る。ただし i386 の
# GENERIC は PAE でないので 4GB を超えて渡しても使えない。3072 にする。
case $NAME in
i386-*)	MEM=${MEM:-3072} ;;
*)	MEM=${MEM:-8192} ;;
esac
MEM=$MEM DIR=. sh runvm.sh "$NAME" "$PORT"
trap cleanup EXIT INT TERM

$SSH "OVERLAY='$OVERLAY' ETYPE='$ETYPE' sh -s" <<'GUEST'
set -e
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/pkg/bin:/usr/pkg/sbin
export PATH

echo "=== 素性 ==="
uname -a
sysctl -n hw.ncpu
sysctl -n hw.machine hw.machine_arch
df -h / /usr | sed 's/^/  /'

echo "=== pkgsrc を用意する ==="
# cdn の current/pkgsrc.tar.gz は数日遅れる。GitHub の mirror の trunk を
# 使う。mirror は変換されたものなので pkgsrc の正ではない (正は CVS)。
# 建てるためだけに使い、送る diff は CVS から取ること。
if [ ! -d /usr/pkgsrc/mk ]; then
	ftp -o /tmp/pkgsrc.tar.gz \
		https://codeload.github.com/NetBSD/pkgsrc/tar.gz/refs/heads/trunk
	tar xzf /tmp/pkgsrc.tar.gz -C /usr
	rm -f /tmp/pkgsrc.tar.gz
	rmdir /usr/pkgsrc 2>/dev/null || true
	if [ -d /usr/pkgsrc-trunk ]; then mv /usr/pkgsrc-trunk /usr/pkgsrc; fi
fi
[ -d /usr/pkgsrc/mk ] || { echo "!! /usr/pkgsrc/mk が無い"; ls /usr | head; exit 1; }

# EMACS_TYPE が木に無いと、落ちるのは modules.mk の奥で、出るのは
# Cannot open /version.mk という読めない文になる。先に見て止める。
if ! grep -q "${ETYPE}@" /usr/pkgsrc/editors/emacs/modules.mk; then
	echo "!! この pkgsrc に EMACS_TYPE=$ETYPE が無い"
	sed -n '/^_EMACS_VERSIONS_ALL=/,/^$/p' /usr/pkgsrc/editors/emacs/modules.mk
	exit 1
fi

echo "=== overlay を被せる ==="
cd /tmp
ftp -o overlay.tar.gz "$OVERLAY"
tar xzf overlay.tar.gz
rm -rf /usr/pkgsrc/zakinko
mv pkgsrc-zakinko-main /usr/pkgsrc/zakinko
# 無いまま進むと「測っていないのに測ったような出力」になる。先に見て止める。
for d in mozc-server333 mozc-elisp333; do
	[ -d /usr/pkgsrc/zakinko/$d ] || { echo "!! overlay に $d が無い"; exit 1; }
done
ls -d /usr/pkgsrc/zakinko/mozc-server333 /usr/pkgsrc/zakinko/mozc-elisp333

echo "=== mk.conf ==="
J=$(sysctl -n hw.ncpu)
cat >> /etc/mk.conf <<EOF
MAKE_JOBS=	$J
BATCH=		yes
ALLOW_VULNERABLE_PACKAGES=	yes
DEPENDS_TARGET=	package-install
FETCH_TIMEOUT=	60
PKG_DEVELOPER=	no
EMACS_TYPE=	$ETYPE
EOF
tail -8 /etc/mk.conf | sed 's/^/  /'

echo
echo "##### 1. gyp の configure が通るか #####"
cd /usr/pkgsrc/zakinko/mozc-server333
V=$(make show-var VARNAME=PKGNAME 2>/dev/null)
[ -n "$V" ] || { echo "!! PKGNAME が取れない。ここで止める"; exit 1; }
echo "  PKGNAME = $V"
echo "  OSDEST  = [$(make show-var VARNAME=OSDEST 2>/dev/null)]"
if make configure >/tmp/conf.log 2>&1; then
	echo 'RESULT configure: 通った'
else
	echo 'RESULT configure: 落ちた'
	tail -40 /tmp/conf.log
	exit 1
fi
echo "--- gyp に渡った値 ---"
grep -oE 'target_platform=[A-Za-z]+|use_qt=[A-Z]+|-D version=[0-9.]+' /tmp/conf.log \
	| sort -u | sed 's/^/  /'
echo "--- 版の末桁 (bazel と揃っていないと client が server を拒む) ---"
grep -h 'Version string is' /tmp/conf.log | sed 's/^/  /'

echo
echo "##### 2. 建つか #####"
if make package-install >/tmp/server.log 2>&1; then
	echo 'RESULT mozc-server333: 通った'
else
	echo 'RESULT mozc-server333: 落ちた'
	tail -40 /tmp/server.log
	exit 1
fi
grep -oE '^\[[0-9]+/[0-9]+\] LINK mozc_server' /tmp/server.log | sed 's/^/  /'

cd /usr/pkgsrc/zakinko/mozc-elisp333
echo "DEPENDS:"; make show-depends 2>/dev/null | sed 's/^/  /'
if make package-install >/tmp/elisp.log 2>&1; then
	echo 'RESULT mozc-elisp333: 通った'
else
	echo 'RESULT mozc-elisp333: 落ちた'
	tail -40 /tmp/elisp.log
	exit 1
fi

echo
echo "##### 3. 出来たもの #####"
pkg_info | grep -iE 'mozc|emacs' | sed 's/^/  /'
for f in /usr/pkg/libexec/mozc_server /usr/pkg/bin/mozc_emacs_helper; do
	echo "--- $f ---"
	ls -l $f
	file $f | sed 's/^/  /'
	ldd $f | sed 's/^/  /'
done
echo "--- X11 を引いていないか (引いていれば gtk や qt が出る) ---"
grep -ciE 'gtk|qt6-qtbase|/usr/X11R7' /tmp/elisp.log

echo
echo "##### 4. 実際に打てるか #####"
# helper の protocol を直に叩く。n i h o n g o を送って preedit を見る。
printf '(1 CreateSession)\n(2 SendKey 1 110)\n(3 SendKey 1 105)\n(4 SendKey 1 104)\n(5 SendKey 1 111)\n(6 SendKey 1 110)\n(7 SendKey 1 103)\n(8 SendKey 1 111)\n' \
	| /usr/pkg/bin/mozc_emacs_helper > /tmp/conv.out 2>&1 || true
echo "--- helper の応答 (末尾) ---"
tail -2 /tmp/conv.out | sed 's/^/  /'
if grep -q '日本語' /tmp/conv.out; then
	echo 'RESULT 変換: 通った'
else
	echo 'RESULT 変換: 落ちた'
	cat /tmp/conv.out | sed 's/^/  /'
	echo "--- helper の log ---"
	cat ~/.config/mozc/mozc_emacs_helper.log 2>/dev/null | tail -20 | sed 's/^/  /'
	exit 1
fi
GUEST
