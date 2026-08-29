#!/bin/sh
#
# mozc 3.34.6239 を gyp で建てる。i386 で通るかを見るのが主目的。
#
#	sh ci/netbsd-mozc334.sh [イメージ名] [EMACS_TYPE]
#	例: sh ci/netbsd-mozc334.sh i386-11.0 emacs30nox
#
# 3.34.6239 に gyp は入っていない。src/build_mozc.py も src/gyp/ も .gyp も
# 一本も無く、建て方は bazel だけである。消えたのは 3.34 ではなく 3.33.6133
# で、その一つ前の 3.33.6089 が gyp を積んだ最後のタグになる。
#
# zakinko/mozc-server334 は 6089 の tarball をもう一本取り、gyp の足場だけを
# 3.34.6239 の木へ流し込む。被せる規則は「6089 に在って 3.34 に無いものだけ」
# の一つで足りる。詳しくは doc/audit.md の
# 「3.34 に GYP を戻せば、i386 の壁は消える」を見よ。
#
# i386 が本題である。bazel は singlejar の
#
#	#error This code for 64 bit Unix.
#
# で 32bit を拒むので、3.34 を bazel で i386 に載せる道は無い。gyp なら
# bazel を一度も呼ばないので、この一行は効かない。効かないことと、実際に
# 建つことは別である。それを測るのがこの script である。
#
# amd64 では techne で確かめてある。690/690 まで建ち、mozc_emacs_helper から
# nihongo が 日本語 に変換されるところまで見た。i386 は未測である。
#
# 測るのは四つ。
#
#   1. 6089 の足場が 3.34 の木に載ること (.gyp が 89 本、build_mozc.py が在る)
#   2. gyp の configure が通ること (target_platform=NetBSD)
#   3. mozc_server と mozc_emacs_helper が建ち、32bit の ELF であること
#   4. 実際に日本語が打てること
#
# ci/netbsd-mozc334.sh と同じ作り。あちらが踏んだ穴 — root では測れない、
# profile を先に作る、sysctl の MIB を先に測る、枝の名前をゲストに渡す —
# はそのまま引き継いでいる。

set -eu

NAME=${1:-i386-11.0}
ETYPE=${2:-emacs30nox}
IMGREPO=${IMGREPO:-zakinko/netbsd-ci-images}
IMGTAG=${IMGTAG:-images}
IMGREF=${IMGREF:-main}
PORT=${PORT:-2334}
# pkgsrc は四半期枝に固定する。trunk だと回した日で結果が変わり、NetBSD の
# 版差を見たいのに pkgsrc 側の版差が混ざる。binary package も同じ枝の set が
# 在るので、木と道具の版が揃う。
PKGSRC_BRANCH=${PKGSRC_BRANCH:-pkgsrc-2026Q2}
PKGSRC_QUARTER=${PKGSRC_QUARTER:-2026Q2}
WORK=${WORK:-$PWD/.vm-mozc334}
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

$SSH "OVERLAY='$OVERLAY' ETYPE='$ETYPE' \
	PKGSRC_BRANCH='$PKGSRC_BRANCH' PKGSRC_QUARTER='$PKGSRC_QUARTER' sh -s" <<'GUEST'
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
# 空のまま進むと URL が refs/heads/ で終わり、ftp は 404 とだけ言う。
# 枝の名前を間違えたのか変数が渡っていないのかが読めないので、先に見て止める。
[ -n "$PKGSRC_BRANCH" ] || { echo "!! PKGSRC_BRANCH が空。ゲストに渡っていない"; exit 1; }
[ -n "$PKGSRC_QUARTER" ] || { echo "!! PKGSRC_QUARTER が空"; exit 1; }
echo "  枝 $PKGSRC_BRANCH / binary set の四半期 $PKGSRC_QUARTER"
# cdn の current/pkgsrc.tar.gz は数日遅れるので GitHub の mirror を使う。
# trunk ではなく四半期枝を取る。trunk だと回した日で木が変わり、NetBSD の
# 版差を見たいのに pkgsrc 側の版差が混ざる。四半期枝には同じ枝で建てられた
# binary package の set もあるので、木と道具の版が揃う。
#
# mirror は変換されたものなので pkgsrc の正ではない (正は CVS)。建てる
# ためだけに使い、送る diff は CVS から取ること。
if [ ! -d /usr/pkgsrc/mk ]; then
	ftp -o /tmp/pkgsrc.tar.gz \
		"https://codeload.github.com/NetBSD/pkgsrc/tar.gz/refs/heads/$PKGSRC_BRANCH"
	tar xzf /tmp/pkgsrc.tar.gz -C /usr
	rm -f /tmp/pkgsrc.tar.gz
	rmdir /usr/pkgsrc 2>/dev/null || true
	for d in /usr/pkgsrc-trunk /usr/pkgsrc-$PKGSRC_BRANCH; do
		[ -d "$d" ] && mv "$d" /usr/pkgsrc
	done
fi
[ -d /usr/pkgsrc/mk ] || { echo "!! /usr/pkgsrc/mk が無い"; ls /usr | head; exit 1; }

# pkgsrc-2026Q2 の editors/emacs30-nox11/version.mk が
#
#	_EMACS_REQD=	emacs30-no-x11>=30.1<31
#
# と書いている。同じ package の PKGNAME は
#
#	PKGNAME=	${DISTNAME:S/emacs/emacs30/:S/-/-nox11-/}   = emacs30-nox11-30.2
#
# なので、この依存は満たしようがない。EMACS_TYPE=emacs30nox を使う
# package は emacs を建て終わったあとで
#
#	pkg_add: package `emacs30-nox11-30.2' already recorded as installed
#	ERROR: [depends.mk] A package matching ``emacs30-no-x11>=30.1<31''
#	ERROR:     should be installed, but one cannot be found.
#
# で落ちる。一時間建ててから落ちるので高くつく。emacs21/26/27/28/29 の
# nox11 は揃っていて、壊れているのは emacs30 の一本だけ。trunk では直って
# いるので、四半期枝を使う間だけの回避。直っている枝では何も起きない。
V=/usr/pkgsrc/editors/emacs30-nox11/version.mk
if grep -q 'emacs30-no-x11>' $V 2>/dev/null; then
	echo "  pkgsrc-$PKGSRC_QUARTER の emacs30-nox11/version.mk を直す"
	sed 's/emacs30-no-x11>/emacs30-nox11>/' $V > $V.new && mv $V.new $V
	grep '_EMACS_REQD' $V | sed 's/^/    /'
fi

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
# 334 は zakinko/ に置いたまま測る。333 は送る先が inputmethod/ と決まって
# いるのでそこへ動かしているが、334 はまだ出す先が決まっていない。
# Makefile.common の DISTINFO_FILE と PATCHDIR も zakinko/ を指している。
# 無いまま進むと「測っていないのに測ったような出力」になる。先に見て止める。
for d in mozc-server334 mozc-elisp334; do
	[ -d /usr/pkgsrc/zakinko/$d ] || { echo "!! overlay に $d が無い"; exit 1; }
done
ls -d /usr/pkgsrc/zakinko/mozc-server334 /usr/pkgsrc/zakinko/mozc-elisp334

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
# 木と同じ枝の set を使う。無ければ枝なしに落ちる (古い release には
# 四半期の set が無いことがある)。
BINPKG=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$(uname -p)/${REL}_${PKGSRC_QUARTER}/All
if ! ftp -o /dev/null "$BINPKG/" 2>/dev/null; then
	echo "  ${REL}_${PKGSRC_QUARTER} の set が無いので $REL に落ちる"
	BINPKG=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$(uname -p)/$REL/All
fi
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
# 入れた emacs が、mozc-elisp334 が要求するものと同じ名前かを見る。
# 名前が違っても pkg_info -e は通るので、上の輪では気づけない。ここで
# 見ておかないと、emacs を一時間かけて建て終わったあとの depends.mk で
# 落ちる。pkgsrc-2026Q2 の emacs30-nox11/version.mk がまさにそれだった。
EREQ=$(cd /usr/pkgsrc/zakinko/mozc-elisp334 && 	make show-var VARNAME=DEPENDS 2>/dev/null | tr ' ' '\n' | grep '^emacs')
echo "  mozc-elisp334 が要る emacs: ${EREQ:-(取れなかった)}"
if [ -n "$EREQ" ] && ! pkg_info -e "${EREQ%%:*}" >/dev/null 2>&1; then
	echo "!! 入れた $EPKG は ${EREQ%%:*} を満たさない"
	pkg_info -e 'emacs*' | sed 's/^/    入っている: /'
	exit 1
fi
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
echo "##### 0. 6089 の足場が 3.34 の木に載ったか #####"
# 3.34 に gyp は無い。Makefile.common の post-extract が 3.33.6089 の tarball
# から足場だけを写す。ここが空振りしていると、この先は「gyp が無い」ではなく
# 「build_mozc.py が無い」という分かりにくい落ち方をする。先に見て止める。
cd /usr/pkgsrc/zakinko/mozc-server334
make patch >/tmp/patch.log 2>&1 || { echo 'RESULT patch: 落ちた'; tail -30 /tmp/patch.log; exit 1; }
S=$(make show-var VARNAME=WRKSRC 2>/dev/null)
echo "  WRKSRC = $S"
N=$(find "$S" -name '*.gyp' -o -name '*.gypi' 2>/dev/null | grep -vc third_party || true)
echo "  .gyp / .gypi = $N 本 (6089 と同じなら 89)"
for f in build_mozc.py gyp/common.gypi protobuf/protobuf.gyp protobuf/custom_protoc_main.cc; do
	if [ -e "$S/$f" ]; then echo "  有 $f"; else echo "  !! 無い $f"; exit 1; fi
done
[ "$N" = 89 ] || echo "::warning::.gyp の数が 89 ではない ($N)"
if grep -qiE 'ignoring|reject|hunk.*fail' /tmp/patch.log; then
	echo '!! 当て物が当たっていない'; grep -iE 'ignoring|reject|hunk' /tmp/patch.log | head -10; exit 1
fi
echo "  当て物 $(ls /usr/pkgsrc/zakinko/mozc-server334/patches | wc -l) 本、reject 無し"

echo
echo "##### 1. gyp の configure が通るか #####"
cd /usr/pkgsrc/zakinko/mozc-server334
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
	echo 'RESULT mozc-server334: 通った'
else
	echo 'RESULT mozc-server334: 落ちた'
	tail -40 /tmp/server.log
	exit 1
fi
grep -oE '^\[[0-9]+/[0-9]+\] LINK mozc_server' /tmp/server.log | sed 's/^/  /'

cd /usr/pkgsrc/zakinko/mozc-elisp334
echo "DEPENDS:"; make show-depends 2>/dev/null | sed 's/^/  /'
if make package-install >/tmp/elisp.log 2>&1; then
	echo 'RESULT mozc-elisp334: 通った'
else
	echo 'RESULT mozc-elisp334: 落ちた'
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
# と進んで Run() が -1 で戻る。main() は戻り値に関係なく Finalize() を呼ぶ。
#
# ここで落ちていた。patch-base_singleton.cc を入れる前の 3.33 は
# FinalizeSingletons が 256 個の配列を全部まわって、埋まっていない
# スロットの null を呼んでいた。i386 で追っていた core はこれで、
# amd64 でも同じ backtrace が出る。i386 固有ではない。
#
# 当て物が入った今は -1 で静かに戻るだけになる。それでも profile は
# 要る。無ければ server は起動しないので、変換はどのみち通らない。
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
	#   server が居ない + core がある       → singleton の当て物が効いていない
	#
	# 「照合で拒まれた」は ipc_path_manager が sysctl KERN_PROC_PATHNAME で
	# 取った server の実 path を、client が期待する
	# base/system_util.cc の MOZC_SERVER_DIR (= /usr/pkg/libexec) と
	# 突き合わせて弾く形。work の binary を直に起こすと必ずこれになるので、
	# 変換は install したものでしか測れない。CI がその唯一の場所になる。
	# server を直に起こして stderr を見る。
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
		B=/usr/pkgsrc/zakinko/mozc-server334/work/mozc-3.33.6089/src/out_bsd/Release/mozc_server
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
