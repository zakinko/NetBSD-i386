#!/bin/sh
#
# NetBSD/i386 の実機で sysutils/augeas だけを建てて make test まで回す。
#
#	sh ci/netbsd-augeas.sh [イメージ名]
#	例: sh ci/netbsd-augeas.sh i386-11.0
#
# build.yml は roles に並んだもの全部を建てるので、他の package が転けたり
# rust の依存を取り続けたりすると augeas まで順番が回らない。send-pr に
# 書く数字が要るだけなので、augeas 一つに絞って回す。
#
# イメージは netbsd-ci-images の release から落とす。起動と停止はあちらの
# スクリプトをそのまま使う。

set -eu

NAME=${1:-i386-11.0}
IMGREPO=${IMGREPO:-zakinko/netbsd-ci-images}
IMGTAG=${IMGTAG:-images}
IMGREF=${IMGREF:-main}
PORT=${PORT:-2225}
WORK=${WORK:-$PWD/.vm-augeas}
OVERLAY=${OVERLAY:-https://codeload.github.com/zakinko/pkgsrc-zakinko/tar.gz/refs/heads/main}

mkdir -p "$WORK"
cd "$WORK"

echo "=== $NAME を用意する ==="
RAW=https://raw.githubusercontent.com/$IMGREPO/$IMGREF
for f in runvm.sh stopvm.sh; do
	[ -s "$f" ] || curl -fsSL -o "$f" "$RAW/$f"
done
REL=https://github.com/$IMGREPO/releases/download/$IMGTAG
for f in $NAME.qcow2 $NAME.qemu; do
	[ -s "$f" ] || { echo "--- $f を落とす ---"; curl -fsSL -o "$f" "$REL/$f"; }
done

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
     -o BatchMode=yes -o LogLevel=ERROR -i $WORK/$NAME.id -p $PORT root@127.0.0.1"

cleanup() {
	rc=$?
	DIR=. sh stopvm.sh "$NAME" > /dev/null 2>&1 || true
	exit $rc
}

echo "=== 起動 ==="
DIR=. sh runvm.sh "$NAME" "$PORT"
trap cleanup EXIT INT TERM

$SSH "OVERLAY='$OVERLAY' sh -s" <<'GUEST'
set -e
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/pkg/bin:/usr/pkg/sbin
export PATH

echo "=== 素性 ==="
uname -a
df -h / /usr | sed 's/^/  /'

echo "=== pkgsrc を用意する ==="
if [ ! -d /usr/pkgsrc/mk ]; then
	# ゲストに IPv6 の経路が無いのに ftp(1) が AAAA を掴んで
	# "No route to host" になる。-4 で塞ぐ。
	ftp -4 -o /tmp/pkgsrc.tar.gz http://cdn.netbsd.org/pub/pkgsrc/current/pkgsrc.tar.gz
	tar xzf /tmp/pkgsrc.tar.gz -C /usr
	rm -f /tmp/pkgsrc.tar.gz
fi

echo "=== overlay を被せる ==="
cd /tmp
ftp -4 -o overlay.tar.gz "$OVERLAY"
tar xzf overlay.tar.gz
# pkgsrc-zakinko の構成が変わり、当て物は repo 直下の augeas/ にある。
# 以前は overlay/sysutils/augeas/ だった。
cp -Rf pkgsrc-zakinko-main/augeas/. /usr/pkgsrc/sysutils/augeas/
ls /usr/pkgsrc/sysutils/augeas/patches | sed 's/^/  /'

echo "=== 道具と依存を binary package で入れる ==="
# augeas が引くのは libxml2 と readline と libtool-base ほかで、ソースから
# 建てると VM の中で二十分から三十分かかる。測っているのは augeas の当て物と
# lens であって依存の build ではないので、先に binary で入れて pkgsrc には
# 「found」と言わせる。augeas 本体はソースから建てるので測るものは変わらない。
REL=$(uname -r | sed 's/_.*//')
BINPKG=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$(uname -p)/$REL/All
echo "  $BINPKG"
# PKG_PATH は pkg_add に渡すときだけ立てる。export したまま make を走らせると
# bsd.pkg.mk が「Please unset PKG_PATH before doing pkgsrc work!」で止める。
for p in digest mktools pkgconf libtool-base readline libxml2; do
	env PKG_PATH="$BINPKG" pkg_add -U "$p" 2>&1 | grep -vE '^$' | head -2 | sed "s/^/    $p: /"
	pkg_info -e "$p" >/dev/null 2>&1 || echo "  !! $p は binary で入らなかった (ソースから建てることになる)"
done
unset PKG_PATH

echo "=== digest を用意する ==="
# 素のイメージに digest は入っていない。makepatchsum はこれを呼ぶので、
# 無いと SHA1 が書けず distinfo が空のまま通ってしまう。すると pkgsrc は
# 当て物を無視して建て、lens が一本も入らない。build は通るので気付き
# にくい。OpenBSD の bootstrap でも同じところを踏んだ。
if [ ! -x /usr/pkg/bin/digest ]; then
	( cd /usr/pkgsrc/pkgtools/digest && make install ) >/tmp/digest.log 2>&1 \
	  || { echo '!! digest を建てられなかった'; tail -20 /tmp/digest.log; exit 1; }
fi
ls -l /usr/pkg/bin/digest

echo "=== 当て物の SHA1 を distinfo に入れる ==="
cd /usr/pkgsrc/sysutils/augeas
make makepatchsum
echo "  distinfo の patch 行: $(grep -c '^SHA1 (patch' distinfo)"

echo "=== 建てる ==="
if make >/tmp/build.log 2>&1; then
	echo 'RESULT build: 通った'
	grep -m1 '^dist_lens_DATA' work/augeas-*/Makefile | cut -c1-60 || true
else
	echo 'RESULT build: 落ちた'
	tail -30 /tmp/build.log
	exit 1
fi

echo "=== make test ==="
if make test >/tmp/test.log 2>&1; then
	echo 'RESULT test: 通った'
else
	echo 'RESULT test: 落ちた'
fi
grep -E '^(FAIL|ERROR):' /tmp/test.log | sort -u
grep -E '^# (TOTAL|PASS|SKIP|XFAIL|FAIL|XPASS|ERROR):' /tmp/test.log
echo '--- lens のテスト ---'
grep -E '(PASS|FAIL): lens-(simplevars|shellvars)' /tmp/test.log | sort -u

echo "=== 入れて augtool が lens を見つけるか ==="
if make install >/tmp/install.log 2>&1; then
	echo 'RESULT install: 通った'
else
	echo '!! install に失敗'
	# PLIST の食い違いは「書いてあるのに入っていない」のか「入っている
	# のに書いていない」のかで直し方が逆になる。見出しごと出す。
	grep -nE 'PLIST|check-files|Files? (in|missing)|ERROR|WARNING' /tmp/install.log \
	  | head -40
	echo '--- install.log の末尾 60 行 ---'
	tail -60 /tmp/install.log
fi
echo "  入った lens: $(ls /usr/pkg/share/augeas/lenses/dist/*.aug 2>/dev/null | wc -l) 本"
/usr/pkg/bin/augtool print /files/etc/hosts 2>&1 | head -5 | sed 's/^/  /'

# man は前回どちらの数え方でも 0 だった。入っていないのか、置き場所が
# 違うのか、数え方が誤っているのかを分けて見る。
echo "--- man がどこに入ったか ---"
find /usr/pkg -name 'aug*.1*' 2>/dev/null | head -6 | sed 's/^/    /'
echo "    man1 の中身: $(ls /usr/pkg/share/man/man1 2>/dev/null | head -5 | tr '\n' ' ')"
for f in $(find /usr/pkg -name 'augtool.1*' 2>/dev/null | head -1); do
	echo "    $f を見る"
	case "$f" in
	*.gz) zcat "$f" 2>/dev/null | grep -c '/usr/share/augeas' | sed 's/^/      \/usr\/share\/augeas: /'
	      zcat "$f" 2>/dev/null | grep -c '/usr/pkg/share/augeas' | sed 's/^/      \/usr\/pkg\/share\/augeas: /' ;;
	*)    grep -c '/usr/share/augeas' "$f" | sed 's/^/      \/usr\/share\/augeas: /'
	      grep -c '/usr/pkg/share/augeas' "$f" | sed 's/^/      \/usr\/pkg\/share\/augeas: /' ;;
	esac
done

echo "=== 当て物なしの make test と比べる ==="
# 落ちた八件が配布物自身のものか、こちらが持ち込んだものかは、素の状態の
# 集合が無いと言えない。当て物を外して同じ木で測り直す。
cd /usr/pkgsrc/sysutils/augeas
make clean >/dev/null 2>&1
rm -rf patches
cp distinfo /tmp/distinfo.patched
grep -v '^SHA1 (patch' /tmp/distinfo.patched > distinfo
if make test >/tmp/test-plain.log 2>&1; then
	echo 'RESULT test(当て物なし): 通った'
else
	echo 'RESULT test(当て物なし): 落ちた'
fi
grep -E '^(FAIL|ERROR):' /tmp/test-plain.log | sort -u
grep -E '^# (TOTAL|PASS|SKIP|FAIL):' /tmp/test-plain.log
GUEST
