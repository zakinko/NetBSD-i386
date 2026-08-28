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
# ディスクは既定が ide のエミュレーションで遅い。使い捨ての箱なので virtio を
# 試し、起動しなければ ide に落とす。NetBSD はディスクを vioblk として見るので、
# image の fstab が /dev/dk0 のままだと上がってこない可能性がある。
if [ "${DISKIF:-}" = "" ] && MEM=$MEM DISKIF=virtio DIR=. sh runvm.sh "$NAME" "$PORT" 2>/dev/null; then
	echo "  disk: virtio"
else
	echo "  disk: virtio が駄目だったので ide に落とす"
	DIR=. sh stopvm.sh "$NAME" > /dev/null 2>&1 || true
	MEM=$MEM DIR=. sh runvm.sh "$NAME" "$PORT"
	echo "  disk: ide"
fi
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
# mozc は distfile と work で数 GB 使う。足りないまま走ると、落ちるのは
# 数時間後の見当違いな場所になる。先に見て止める。
AVAIL=$(df -k / | awk 'NR==2 {print int($4/1024)}')
echo "  / の空き: ${AVAIL}MB"
# この image には swap が無い (/dev/dk0 の一区画だけ)。mozc は protobuf と
# abseil を丸ごと組むので、3GB の箱で cc1plus が並ぶと OOM で殺される。
#
#	c++: fatal error: Killed signal terminated program cc1plus
#
# ディスクは 9GB 空いているので、ファイル swap を足しておく。並列度も
# MAKE_JOBS で絞るが、片方だけでは足りないことがある。
if [ "$(swapctl -l 2>/dev/null | grep -c /)" = "0" ]; then
	echo "  swap が無いので 4GB 足す"
	dd if=/dev/zero of=/swap bs=1m count=4096 2>/dev/null
	chmod 600 /swap
	swapctl -a /swap
fi
swapctl -l 2>/dev/null | sed 's/^/  /'

# 素の NetBSD で procfs が mount されるか。mozc の IPC は
# ipc_path_manager.cc が /proc/<pid>/exe を読む当て物を持っているので、
# 無ければ照合が失敗する側に倒れる。
echo "  procfs: $(mount | grep -c procfs) 個 mount / fstab に $(grep -c proc /etc/fstab 2>/dev/null || echo 0) 行"
if [ "$AVAIL" -lt 4000 ]; then
	echo "!! / の空きが ${AVAIL}MB しかない。4000MB は要る"
	exit 1
fi

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

echo "=== 道具を binary package で入れる ==="
# ソースから建てると devel/ninja-build が devel/re2c を、re2c が
# devel/cmake を引き、cmake の bootstrap でゲストの / が溢れる。
#
#	fatal error: error writing to /tmp//ccTu0Mse.s: No space left on device
#	Error when bootstrapping CMake
#
# i386 の binary set に道具は全部在るので、先に入れて pkgsrc には
# 「found」と言わせる。mozc 本体はソースから建てるので、測るものは変わらない。
REL=$(uname -r | sed 's/_.*//')
BINPKG=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$(uname -p)/$REL/All
echo "  $BINPKG"
# EMACS_TYPE (emacs30nox) から package 名 (emacs30-nox11) を作る
EPKG=$(echo "$ETYPE" | sed -e 's/nox$/-nox11/')
# PKG_PATH は pkg_add に渡すときだけ立てる。export したまま make を走らせると
# bsd.pkg.mk が「Please unset PKG_PATH before doing pkgsrc work!」で止める。
for p in ninja-build py313-gyp py313-six "$EPKG"; do
	env PKG_PATH="$BINPKG" pkg_add -U "$p" 2>&1 | grep -vE '^$' | head -2 | sed "s/^/    $p: /"
	pkg_info -e "$p" >/dev/null 2>&1 || { echo "!! $p を binary で入れられなかった"; exit 1; }
done
unset PKG_PATH
pkg_info | egrep -i 'ninja|gyp|six|emacs' | sed 's/^/  /'
df -h / | sed 's/^/  /'

echo "=== mk.conf ==="
# 一度 OOM で落として 2 に絞ったが、あれは swap が無かったためだった。
# いまは 4GB 足してある。bambi (物理 1.0GB、-j1) の実測で cc1plus は
# 1 本あたり 150MB 前後なので、3072MB なら CPU 数ぶん立てても収まる。
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
# i386 では options.mk が gyp を既定にする。それが効いているかを測るのが
# この script の目的なので、i386 では何も足さない。
#
# 64bit の箱で回すと既定は bazel になり、TOOL_DEPENDS が zakinko/bazel9 を
# 引く。あれは bootstrap に二時間から三時間かかるので、測りたいものと
# 関係のない時間を CI が払うことになる。i386 以外では gyp を明示する。
case $(uname -m) in
i386|earm*)	;;
*)		echo 'PKG_OPTIONS.mozc=	gyp' >> /etc/mk.conf
		echo "  $(uname -m) なので PKG_OPTIONS.mozc=gyp を明示した (bazel9 を建てない)" ;;
esac
tail -8 /etc/mk.conf | sed 's/^/  /'

echo
echo "##### 1. gyp の configure が通るか #####"
cd /usr/pkgsrc/zakinko/mozc-server333
V=$(make show-var VARNAME=PKGNAME 2>/dev/null)
[ -n "$V" ] || { echo "!! PKGNAME が取れない。ここで止める"; exit 1; }
echo "  PKGNAME     = $V"
echo "  PKG_OPTIONS = [$(make show-var VARNAME=PKG_OPTIONS 2>/dev/null)]"
echo "  OSDEST      = [$(make show-var VARNAME=OSDEST 2>/dev/null)]"

# options.mk が LP32PLATFORMS を見て gyp を既定にする。i386 でそれが効いて
# いなければ bazel を建てにいってしまい、devel/bazel は 32bit で建たないので
# 何時間か走った末に落ちる。先に見て止める。
case $(uname -p) in
i386)
	case "$(make show-var VARNAME=PKG_OPTIONS 2>/dev/null)" in
	*gyp*)	echo "  (i386 で gyp が既定になっている)" ;;
	*)	echo "!! i386 なのに gyp が既定になっていない"
		echo "   LP32PLATFORMS = $(make show-var VARNAME=LP32PLATFORMS 2>/dev/null)"
		echo "   MACHINE_PLATFORM = $(make show-var VARNAME=MACHINE_PLATFORM 2>/dev/null)"
		exit 1 ;;
	esac
	;;
esac
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
#
# root では測れない。mozc は base/run_level.cc:268 の
#
#	if (::geteuid() == 0) { ... return RunLevel::DENY; }
#
# で root を拒む。root のまま試すと server が入っていても
#
#	((error . session-error)(message . "Session failed"))
#
# になり、server が無いときとまったく同じ見え方になる。VM の中は root なので
# 一般ユーザを作ってそちらで測る。両方出して、区別がつかないことも示す。
# (ci/netbsd-mozc226.sh が先に踏んだ。同じ道を二度通らないために書いておく。)
id mozctest >/dev/null 2>&1 || useradd -m -s /bin/sh mozctest
# profile を先に作る。useradd -m は home を作るだけで .config は作らない。
# mozc は profile が無いと
#   system_util.cc     User profile directory doesn't exist
#   process_mutex.cc   open() failed
#   mozc_server.cc:99  Mozc Server is already running   <- 誤判定
# と進んで Finalize() に入り、FinalizeSingletons で null を呼んで落ちる。
# server が入っていないときと同じ応答になるので、出力だけでは分からない。
su - mozctest -c 'mkdir -p ~/.config/mozc'
su - mozctest -c 'ls -ld ~/.config/mozc' | sed 's/^/  profile: /'
cat > /tmp/conv.sh <<'EOS'
printf '(1 CreateSession)\n(2 SendKey 1 110)\n(3 SendKey 1 105)\n(4 SendKey 1 104)\n(5 SendKey 1 111)\n(6 SendKey 1 110)\n(7 SendKey 1 103)\n(8 SendKey 1 111)\n' \
	| /usr/pkg/bin/mozc_emacs_helper
EOS
chmod 755 /tmp/conv.sh

# 変換が落ちたとき、原因は三つある (どれも同じ応答になる)。
#   1. server が入っていない
#   2. root で叩いている              base/run_level.cc の geteuid()==0
#   3. server の照合に失敗している    ipc_path_manager.cc
# 3 は当て物が sysctl KERN_PROC_PATHNAME で server の path を取るので、
# その sysctl がこの箱で効くかを先に測っておく。
cat > /tmp/mib.c <<'EOT'
#include <sys/param.h>
#include <sys/sysctl.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
int main(int argc, char **argv) {
  pid_t pid = (argc > 1) ? (pid_t)atoi(argv[1]) : getpid();
  size_t len; int rc;
  int n4p[] = { CTL_KERN, KERN_PROC_ARGS, (int)pid, KERN_PROC_PATHNAME };
  char buf[1024]; len = sizeof(buf);
  rc = sysctl(n4p, 4, buf, &len, NULL, 0);
  printf("pid=%d KERN_PROC_PATHNAME rc=%d errno=%s len=%zu path=\"%s\"\n",
         (int)pid, rc, rc<0?strerror(errno):"-", len, rc==0?buf:"");
  return 0;
}
EOT
echo "--- sysctl KERN_PROC_PATHNAME はこの箱で効くか ---"
cc -o /tmp/mib /tmp/mib.c || echo "  mib.c が建たない"
echo "  自分の pid で:"; /tmp/mib | sed 's/^/    /'

echo "--- 参考: root で叩くと (RunLevel::DENY で拒まれる) ---"
sh /tmp/conv.sh > /tmp/conv-root.out 2>&1 || true
tail -2 /tmp/conv-root.out | sed 's/^/  /'

echo "--- 一般ユーザで叩く ---"
su - mozctest -c 'sh /tmp/conv.sh' > /tmp/conv.out 2>&1 || true
tail -3 /tmp/conv.out | sed 's/^/  /'
if grep -q 'にほんご' /tmp/conv.out; then
	echo 'RESULT 変換: にほんご が出た'
else
	echo 'RESULT 変換: にほんご が出ない'
	cat /tmp/conv.out | sed 's/^/  /'
	# 見え方が同じ Session failed でも原因が違う。まずここで分ける。
	#   server が生きている + socket がある → 照合で拒まれた
	#   server が居ない + socket も無い     → 起動できずに死んだ
	#   server が居ない + core がある       → i386 で落ちている (当て物と無関係)
	# af が amd64 で再現させたのは「profile が作れない HOME で起こすと落ちる」
	# という条件だった。CI は useradd -m で home を作っているので profile は
	# 作れるはずで、そこが食い違っている。server を直に起こして stderr を見る。
	echo "--- profile は作れているか ---"
	su - mozctest -c 'ls -la ~/.config/ 2>&1; ls -la ~/.config/mozc/ 2>&1' \
		| head -20 | sed 's/^/  /'
	echo "--- server を直に起こして stderr を見る ---"
	su - mozctest -c '/usr/pkg/libexec/mozc_server' > /tmp/srv.out 2>&1 &
	sleep 8
	echo "  exit を待たずに 8 秒後の出力:"
	head -20 /tmp/srv.out | sed 's/^/    /'
	pkill -f 'libexec/mozc_server' 2>/dev/null || true

	echo "--- server は生きているか ---"
	if pgrep -lf 'libexec/mozc_server' 2>/dev/null | sed 's/^/  /'; then
		spid=$(pgrep -f 'libexec/mozc_server' | head -1)
		echo "  その pid で sysctl を引けるか (helper がやること):"
		/tmp/mib "$spid" 2>/dev/null | sed 's/^/    /'
	else
		echo "  server は生きていない"
	fi
	echo "--- socket ---"
	ls -a /tmp | grep -E '^\.mozc\.' | sed 's/^/  /' || echo "  (無い)"
	echo "--- core ---"
	ls -l /*core* /home/mozctest/*core* /usr/pkg/libexec/*core* 2>/dev/null | sed 's/^/  /' || echo "  (無い)"
	# core があるなら中身を見る。mozc は MOZC_NO_LOGGING で建っているので log は
	# 出ないが、bt はどこで落ちたかを一行で教えてくれる。VM は job が終わると
	# 消えるので、その場で取っておかないと後から見られない。
	for c in /home/mozctest/mozc_server.core /home/mozctest/*.core; do
		[ -f "$c" ] || continue
		echo "--- bt ($c) ---"
		# /usr/pkg/libexec/mozc_server は INSTALL_PROGRAM が -s で入れるので
		# stripped で、bt が ?? だらけになる。work に未 strip のものが残って
		# いるので、在ればそちらを使う。
		B=/usr/pkgsrc/zakinko/mozc-server333/work/mozc-3.33.6089/src/out_bsd/Release/mozc_server
		[ -f "$B" ] || B=/usr/pkg/libexec/mozc_server
		echo "  binary: $B"
		file "$B" | sed 's/^/  /'
		gdb -batch -ex 'set pagination off' -ex bt -ex 'info registers eip' \
			"$B" "$c" 2>&1 | head -40 | sed 's/^/  /'
		break
	done
	echo "--- helper の log ---"
	find /home/mozctest -name 'mozc_emacs_helper.log' 2>/dev/null | \
		xargs -r tail -20 2>/dev/null | sed 's/^/  /'
	echo "--- server の log ---"
	find /home/mozctest -name 'mozc_server.log' 2>/dev/null | \
		xargs -r tail -20 2>/dev/null | sed 's/^/  /'
	echo "--- server はどこから起動されるか ---"
	ls -l /usr/pkg/libexec/mozc_server | sed 's/^/  /'
	echo "--- この起動で出来た socket ---"
	ls -a /tmp | grep -E '^\.mozc\.' | sed 's/^/  /'
	exit 1
fi
echo "--- 変換候補に 日本語 があるか ---"
if grep -q '日本語' /tmp/conv.out; then echo '  ある'; else echo '  ない'; fi
GUEST
