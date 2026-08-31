#!/bin/sh
#
# NetBSD/amd64 で inputmethod/mozc-elisp226 を建てて、変換まで通す。
#
#	sh ci/netbsd-mozc226.sh [イメージ名] [EMACS_TYPE]
#	例: sh ci/netbsd-mozc226.sh amd64-11.0 emacs30nox
#
# 手元 (techne) では測れないことがあるので CI に持ってきた。emacs は
# bin/ctags などが衝突して複数版を同時に入れられず、mozc-server も 2.26 と
# 2.29 が PKGBASE を共有していて同居できない。一つの箱で三版を測るには
# 入れ替えを繰り返すしかなく、同じ箱を使っている他の作業を巻き込む。
# job ごとに別の VM なら、その全部が消える。
#
# 測るのは四つ。
#
#   1. 上流の mozc-elisp226 が GTK2 と Qt5 を実行時依存に持つこと
#   2. 直したものはそれを持たず、代わりに mozc-server226 を持つこと
#   3. MOZC_GUI_PKGS に名前の無い他の四つが何も変わらないこと
#   4. 実際に日本語が打てること
#
# イメージは netbsd-ci-images の release から落とす。起動と停止はあちらの
# スクリプトをそのまま使う。ci/netbsd-augeas.sh と同じ作り。

set -eu

# cd する前に確定させる。あとで $WORK へ移るので、相対のままだと
# .vm-mozc226/doc/... を探しに行く (実際そうなって四本落とした)。
SRCROOT=$(cd "$(dirname "$0")/.." && pwd)

NAME=${1:-amd64-11.0}
ETYPE=${2:-emacs30nox}
IMGREPO=${IMGREPO:-zakinko/netbsd-ci-images}
IMGTAG=${IMGTAG:-images}
IMGREF=${IMGREF:-main}
PORT=${PORT:-2226}
WORK=${WORK:-$PWD/.vm-mozc226}
# DEEP=1 で、送る PR が主張するうち追加ビルドを要する分も測る。
# 既定では測らない。四本の GUI 版と未修正 server を建てるので二時間ほど延びる。
DEEP=${DEEP:-0}
# GUI 四本の追加ビルドだけを外す。あそこが一番重く、四時間の大半を
# 食う。対の測定 (古い server と新しい helper) だけ急ぎで取りたいとき、
# 上限に当たって何も取れずに終わるより、軽くして確実に取る方がよい。
DEEP_GUI=${DEEP_GUI:-1}
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
# mozc は protobuf と abseil を丸ごと組むので、既定の 4096 では足りない
# ことがある。runner は 16GB あるので広く取る。
# 二本目のディスクを足す。イメージの / は 11G しかなく、未修正の木を
# 建てると gtk2 の依存が gcc14 まで辿って使い切る。実際 105% で落ちた。
# runner 側は 100G 以上空いていて、qcow2 は sparse なので、大きく取っても
# 実際に使うぶんしか減らない。runvm.sh の EXTRAARGS から渡す。
# root が wd0a なので、二本目は wd1 として見える。
SCRATCH=${SCRATCH:-60G}
qemu-img create -f qcow2 "$WORK/scratch.qcow2" "$SCRATCH" >/dev/null 2>&1 \
	&& echo "=== 作業用ディスクを $SCRATCH で足す ===" \
	|| echo "=== 作業用ディスクを作れなかった (11G のまま進む) ==="
EXTRAARGS="-drive file=$WORK/scratch.qcow2,if=ide,format=qcow2,cache=unsafe" \
MEM=${MEM:-8192} DIR=. sh runvm.sh "$NAME" "$PORT"
trap cleanup EXIT INT TERM

# 送る diff そのものを VM へ入れる。overlay の写しではなく、これを当てて
# 建てる。写しは zakinko/ に置くので ${PKGPATH} が変わり、PKGPATH で分ける
# 仕掛けを手元では確かめられない。VM の中なら本来の path で試せる。
# doc/ は履歴から落として .gitignore に入ったので、CI の入力には使えない
# (checkout したところに無い)。追跡される ci/ に置く。中身は
# doc/upstream/pr/mozc-elisp226.pr に載せているものと同じ。
DIFF=${DIFF:-$SRCROOT/ci/mozc-elisp226.diff}
[ -f "$DIFF" ] || { echo "$0: $DIFF が無い" >&2; exit 1; }
echo "=== 送る diff を入れる: $DIFF ($(wc -l < "$DIFF") 行) ==="
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o LogLevel=ERROR -i "$WORK/$NAME.id" -P "$PORT" \
    "$DIFF" root@127.0.0.1:/tmp/mozc226.diff

$SSH "ETYPE='$ETYPE' DEEP='$DEEP' DEEP_GUI='$DEEP_GUI' sh -s" <<'GUEST'
set -e
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/pkg/bin:/usr/pkg/sbin
export PATH

echo "=== 素性 ==="
uname -a
sysctl -n hw.ncpu
df -h / /usr | sed 's/^/  /'

echo "=== pkgsrc を用意する ==="
# cdn の current/pkgsrc.tar.gz ではなく GitHub の mirror の trunk を使う。
# cdn の tarball は数日遅れる。editors/emacs31-nox11 が入ったのは
# 2026-08-25 で、2026-08-22 版の tarball にはまだ無く、EMACS_TYPE を
# emacs31nox にすると _EMACS_PKGDIR_MAP が空に解決されて
#   make: editors/emacs/modules.mk:299: Cannot open /version.mk
# で全部落ちる。emacs31 を登録しているのは modules.mk の rev 1.40
# (2026-08-25) である。三つの job で違う木を使うと比べられなくなるので、
# 三つとも mirror に揃える。
#
# mirror は変換されたものなので pkgsrc の正ではない (正は CVS)。ここは
# 建てるためだけに使う。送る diff は CVS から取ること。
if [ ! -d /usr/pkgsrc/mk ]; then
	ftp -o /tmp/pkgsrc.tar.gz \
		https://codeload.github.com/NetBSD/pkgsrc/tar.gz/refs/heads/trunk
	tar xzf /tmp/pkgsrc.tar.gz -C /usr
	rm -f /tmp/pkgsrc.tar.gz
	# codeload の tarball は pkgsrc-trunk/ に展開される。/usr/pkgsrc が
	# 空で先に在ることがあるので、消してから移す。中身があるなら触らない。
	rmdir /usr/pkgsrc 2>/dev/null || true
	if [ -d /usr/pkgsrc-trunk ]; then mv /usr/pkgsrc-trunk /usr/pkgsrc; fi
fi
[ -d /usr/pkgsrc/mk ] || { echo "!! /usr/pkgsrc/mk が無い"; ls /usr | head; exit 1; }
echo "  mozc-elisp226 の版: $(grep -m1 '\$NetBSD' /usr/pkgsrc/inputmethod/mozc-elisp226/Makefile)"
echo "  modules.mk の版:    $(grep -m1 '\$NetBSD' /usr/pkgsrc/editors/emacs/modules.mk)"

# EMACS_TYPE が木に無いと、落ちるのは modules.mk の奥で、出るのは
# Cannot open /version.mk という読めない文になる。先に見て止める。
if ! grep -q "${ETYPE}@" /usr/pkgsrc/editors/emacs/modules.mk; then
	echo "!! この pkgsrc に EMACS_TYPE=$ETYPE が無い"
	sed -n '/^_EMACS_VERSIONS_ALL=/,/^$/p' /usr/pkgsrc/editors/emacs/modules.mk
	exit 1
fi

# 当てる前に上流の姿を控える。当てたあとでは比べられない。
echo "=== mk.conf ==="
J=$(sysctl -n hw.ncpu)
# i386 の VM で devel/cmake を建てている途中に溢れた。
#   g++: fatal error: Killed signal terminated program cc1plus
#   fatal error: error writing to /tmp//cc5QZPPb.s: No space left on device
# / は 11G 中 9.0G 空いていたので、溢れたのは tmpfs の /tmp である。32bit は
# 一プロセスあたりの上限も低いので、並列度も落とす。
case $(uname -m) in
i386|earm*)	J=2 ;;
esac
echo "  MAKE_JOBS=$J  ($(uname -m))"
mount | grep -E ' /tmp | /var/tmp ' | sed 's/^/  /'
# 一時ファイルは tmpfs ではなくディスクへ。
mkdir -p /var/tmp/ccbuild && chmod 1777 /var/tmp/ccbuild

# swap が無いと cc1plus が殺される。i386 は PAE 無しで物理が 3.5GB 程度に
# 頭打ちなので、qemu に MEM を積んでも届かない。イメージの fstab に swap の
# 行は無いので、/ の空きから作る。
#
#   g++: fatal error: Killed signal terminated program cc1plus
#
# VM は job の終わりに消えるので、外す後始末は要らない。
PHYS=$(sysctl -n hw.physmem64 2>/dev/null || sysctl -n hw.physmem)
echo "  物理: $PHYS  空き: $(df -k / | awk 'NR==2{printf "%.1f GB", $4/1048576}')"
# / は 11G しかなく mozc の展開と build で埋まる。swap を無条件に 4G 取ると
# amd64 の回が展開の途中で No space left on device になった。物理が足りない
# ときだけ、空きを見て控えめに取る。
if [ "$(swapctl -l 2>/dev/null | grep -c /)" = "0" ] && [ "$PHYS" -lt 2147483648 ]; then
	free=$(df -k / | awk 'NR==2{print int($4/1024)}')
	sz=2048
	[ "$free" -gt 8000 ] || sz=1024
	dd if=/dev/zero of=/var/tmp/swapfile bs=1m count=$sz 2>/dev/null
	chmod 600 /var/tmp/swapfile
	swapctl -a /var/tmp/swapfile && echo "  swap を ${sz}M 足した (空き ${free}M)"
fi
swapctl -l 2>/dev/null | sed 's/^/  /'
# 足した二本目を作業用に使う。失敗しても止めない (11G のまま進む)。
WRKOBJ=
if [ -e /dev/wd1a ]; then
	echo "=== 二本目のディスクを作業用にする ==="
	# 失敗の理由を握り潰さない。一度 newfs か mount のどちらで転んだか
	# 分からないまま「11G のまま進む」とだけ出て、原因が追えなかった。
	dkctl wd1 listwedges 2>&1 | sed 's/^/    /' || true
	disklabel wd1 2>&1 | tail -8 | sed 's/^/    /' || true
	# NetBSD の既定 label は全体を a に 4.2BSD で置き、d は unused にする。
	# d を newfs しようとして "partition type is not 4.2BSD" で落ちた。
	: > /tmp/newfs.out; : > /tmp/mount.out
	if newfs -O2 /dev/rwd1a > /tmp/newfs.out 2>&1 \
	   && mkdir -p /scratch \
	   && mount /dev/wd1a /scratch > /tmp/mount.out 2>&1; then
		mkdir -p /scratch/work /scratch/distfiles /scratch/packages
		WRKOBJ=/scratch/work
		df -h /scratch | sed 's/^/  /'
	else
		echo "  newfs か mount に失敗した (11G のまま進む)"
		# 診断で run を殺さない。mount が走らないと mount.out が無く、
		# それを読む sed が set -e で落ちて、ここまでの測定ごと消えた。
		echo "    newfs:"; sed 's/^/      /' /tmp/newfs.out 2>/dev/null || true
		echo "    mount:"; sed 's/^/      /' /tmp/mount.out 2>/dev/null || true
	fi
else
	echo "=== 二本目のディスクが見えない (11G のまま進む) ==="
	sysctl -n hw.disknames 2>/dev/null | sed 's/^/  disks: /'
fi

cat >> /etc/mk.conf <<EOF
MAKE_JOBS=	$J
MAKE_ENV+=	TMPDIR=/var/tmp/ccbuild
CONFIGURE_ENV+=	TMPDIR=/var/tmp/ccbuild
BATCH=		yes
ALLOW_VULNERABLE_PACKAGES=	yes
DEPENDS_TARGET=	package-install
FETCH_TIMEOUT=	60
PKG_DEVELOPER=	no
EMACS_TYPE=	$ETYPE
# distfile は NetBSD の CDN からだけ取る。上流の配布元に直接行くと、
# 届かない先が混ざって落ちる。実際 emacs30nox の回はここで死んだ。
#
#	=> Fetching cmake-4.4.3.tar.gz
#	ftp: Can't connect to \`66.194.253.25:443': Connection refused
#	ftp: Can't connect to \`2a04:4e42:94::262:443': No route to host
#
# ninja-build -> re2c -> cmake の連鎖で cmake.org に行こうとしたもので、
# 建てているものとは関係がない。CDN は pkgsrc が配る distfile を一通り
# 持っているので、そこに寄せる。
MASTER_SITE_OVERRIDE=	https://cdn.NetBSD.org/pub/pkgsrc/distfiles/
EOF
if [ -n "$WRKOBJ" ]; then
	cat >> /etc/mk.conf <<EOF
WRKOBJDIR=	$WRKOBJ
DISTDIR=	/scratch/distfiles
PACKAGES=	/scratch/packages
EOF
	echo "  WRKOBJDIR を $WRKOBJ にした"
fi
tail -12 /etc/mk.conf | sed 's/^/  /'

# 建てたいのは mozc だけ。道具は binary で入れる。ninja-build は re2c を、
# re2c は cmake を引き、その cmake の bootstrap で /tmp を数 GB 使う。二度
# そこで潰した (一度は No space left on device、一度は cc1plus が Killed)。
# 測る対象はソースから建てるので、測るものは変わらない。
echo "=== 道具を binary で入れる ==="
A=$(uname -m); R=$(uname -r | sed 's/_.*//')
# export したままにしないこと。pkgsrc は
#   ERROR: [bsd.pkg.mk] Please unset PKG_PATH before doing pkgsrc work!
# で止まる。pkg_add に env で渡すだけにする。
BINPKG="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$A/$R/All"
echo "  $BINPKG"
for p in $( ( cd /usr/pkgsrc/inputmethod/mozc-server226 && make show-var VARNAME=TOOL_DEPENDS 2>/dev/null ) \
            | tr ' ' '\n' | sed 's/:.*//;s/[<>=].*//;s/-\[0-9\].*//' | grep . | sort -u ); do
	printf '  %-16s ' "$p"
	timeout 900 env PKG_PATH="$BINPKG" pkg_add -U "$p" >/dev/null 2>&1 \
		&& echo "入った" || echo "取れず (ソースから建つ)"
done

# 「当てる前」は mk.conf を書いたあとに撮る。前に撮ると、MAKE_JOBS や
# TMPDIR を足したぶんが差として出てしまう。実際それで 0 行のはずが 33 行に
# なった。比べたいのは diff の影響だけである。
echo "=== 当てる前の上流 ==="
for p in mozc-elisp226 mozc-server226; do
	echo "  --- $p ---"
	( cd /usr/pkgsrc/inputmethod/$p
	  echo "    USE_X11 = [$(make show-var VARNAME=USE_X11 2>/dev/null)]"
	  make show-depends 2>/dev/null | sed 's/^/      /' )
done
for p in ibus-mozc226 mozc-renderer226 mozc-tool226 uim-mozc226; do
	( cd /usr/pkgsrc/inputmethod/$p && make show-all 2>/dev/null ) > /tmp/before.$p
done

# 送る PR は「直す前の server と直した後の helper は出会えない」と書いている。
# ここは diff を当てる「前」でなければならない。当てた後に建てると修正済みの
# binary を「未修正」と呼ぶことになり、対の測定が成立しない。一度そうなった。
# そのときも結果は session_error で主張どおりに見えたが、/tmp から起こした
# server が path 照合に落ちただけで、socket 名が .session だったのが唯一の兆候。
# それを測るには未修正の server の binary が要る。木がまだ未修正のいまだけ
# 取れるので、ここで建てて退避しておく。あとで対にする。
if [ "$DEEP" = 1 ]; then
	echo
	echo "--- (DEEP) 未修正の mozc-server226 を建てて binary を退避する ---"
	# 未修正の木は gtk2 と qt5 を buildlink する。この PR が直そうとして
	# いるのがまさにそれで、放っておくと gdk-pixbuf2 -> libjpeg-turbo ->
	# nasm -> gcc14 まで辿り、11G の disk を使い切って落ちる。実際に
	# 105% まで行って落ちた。要らない依存を測るために建てる筋合いはないので
	# binary で入れる。測る対象 (mozc の ipc) はソースから建つので変わらない。
	echo "    GUI 側の依存を binary で入れる"
	# pkg_add には時間切れが無い。取得先が黙ると落ちずに待ち続けるので、
	# 一度 qt5-qtbase で五時間無音のまま上限に当たり、測定が一つも取れずに
	# 終わった。待つ上限を外から付ける。取れなければ「取れず」で先へ進む
	# ので、ここで止まる理由はない。
	for q in glib2 gtk2+ qt5-qtbase zinnia curl; do
		printf '      %-12s ' "$q"
		if timeout 900 env PKG_PATH="$BINPKG" pkg_add -U "$q" >/dev/null 2>&1; then
			echo "入った"
		else
			rc=$?
			[ "$rc" = 124 ] && echo "★ 15 分で時間切れ" || echo "取れず"
		fi
	done
	df -h / | sed 's/^/      /'
	cd /usr/pkgsrc/inputmethod/mozc-server226
	if make package-install > /tmp/b-unpatched.log 2>&1; then
		cp /usr/pkg/libexec/mozc_server /root/mozc_server.unpatched
		echo "  退避した: $(ls -l /root/mozc_server.unpatched | awk '{print $5}') バイト"
		pkg_delete -f mozc-server-2.26.4282.100nb45 >/dev/null 2>&1 \
			|| pkg_delete -f 'mozc-server-2.26*' >/dev/null 2>&1 || true
		make clean > /dev/null 2>&1 || true
	else
		echo "  ★ 未修正 server が建たない"; tail -20 /tmp/b-unpatched.log | sed 's/^/    /'
	fi
fi

echo "=== 送る diff を当てる ==="
cd /usr/pkgsrc
patch -p0 -C < /tmp/mozc226.diff || { echo "!! 当たらない"; exit 1; }
patch -p0    < /tmp/mozc226.diff
find /usr/pkgsrc/inputmethod -name '*.orig' -delete
echo "  当てたファイル:"
grep '^--- ' /tmp/mozc226.diff | sed 's/^--- /    /'

echo "=== 道具を binary package で入れる ==="
# mozc-elisp226 が引くのは 11 個で、そのうち emacs30-nox11 と python313 は
# ソースから建てると VM の中で三十分から一時間ずつかかる。測っているのは
# mozc 本体の当て物であって依存の build ではないので、道具は先に binary で
# 入れて pkgsrc には「found」と言わせる。mozc-server226 と mozc-elisp226 は
# ソースから建てるので、測るものは変わらない。
#
# netbsd-mozc333.sh が先に同じことをしている。あちらは ninja が re2c を、
# re2c が cmake を引いて / が溢れたのがきっかけだった。
REL=$(uname -r | sed 's/_.*//')
BINPKG=https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$(uname -p)/$REL/All
echo "  $BINPKG"
# EMACS_TYPE (emacs30nox) から package 名 (emacs30-nox11) を作る
EPKG=$(echo "$ETYPE" | sed -e 's/nox$/-nox11/')
# PKG_PATH は pkg_add に渡すときだけ立てる。export したまま make を走らせると
# bsd.pkg.mk が「Please unset PKG_PATH before doing pkgsrc work!」で止める。
for p in gmake ninja-build pkgconf py313-gyp py313-six "$EPKG"; do
	timeout 900 env PKG_PATH="$BINPKG" pkg_add -U "$p" 2>&1 | grep -vE '^$' | head -2 | sed "s/^/    $p: /"
	pkg_info -e "$p" >/dev/null 2>&1 || echo "  !! $p は binary で入らなかった (ソースから建てることになる)"
done
unset PKG_PATH
pkg_info | egrep -i 'gmake|ninja|gyp|six|python|emacs' | sed 's/^/  /'
df -h / | sed 's/^/  /'

echo
echo "##### 1. 上流の mozc-elisp226 は何を引くか #####"
cd /usr/pkgsrc/inputmethod/mozc-elisp226
echo "USE_X11 = [$(make show-var VARNAME=USE_X11 2>/dev/null)]"
make show-depends 2>/dev/null | sed 's/^/  /'

echo
echo "##### 2. GUI を切らない四つは変わらないか #####"
# 当てる前に控えた show-all と、当てたあとの同じ package を直に比べる。
# 写しを作らないので ${PKGPATH} が本物のままで、PKGPATH で分ける仕掛けが
# 本当に効いているかどうかまで一緒に測れる。
for p in ibus-mozc226 mozc-renderer226 mozc-tool226 uim-mozc226; do
	( cd /usr/pkgsrc/inputmethod/$p && make show-all 2>/dev/null ) > /tmp/after.$p
	n=$(wc -l < /tmp/before.$p)
	d=$(diff /tmp/before.$p /tmp/after.$p | grep -c '^[<>]' || true)
	printf '  %-18s %5s 行中 差 %s 行\n' "$p" "$n" "$d"
	if [ "$d" != "0" ]; then
		diff /tmp/before.$p /tmp/after.$p | grep '^[<>]' | head -12 | sed 's/^/    /'
	fi
done
echo "--- PKGPATH で分ける仕掛けが効いているか (六つとも) ---"
for p in mozc-server226 mozc-elisp226 ibus-mozc226 mozc-renderer226 mozc-tool226 uim-mozc226; do
	printf '  %-18s USE_X11=[%s] MOZC_GYP_ARGS=[%s]\n' "$p" \
	  "$(cd /usr/pkgsrc/inputmethod/$p && make show-var VARNAME=USE_X11 2>/dev/null)" \
	  "$(cd /usr/pkgsrc/inputmethod/$p && make show-var VARNAME=MOZC_GYP_ARGS 2>/dev/null)"
done

echo "##### 3. 直した mozc-elisp226 を建てる #####"
cd /usr/pkgsrc/inputmethod/mozc-elisp226
echo "USE_X11 = [$(make show-var VARNAME=USE_X11 2>/dev/null)]"
echo "DEPENDS:"; make show-depends 2>/dev/null | sed 's/^/  /'
if make package-install >/tmp/build.log 2>&1; then
	echo 'RESULT build: 通った'
else
	echo 'RESULT build: 落ちた'
	tail -40 /tmp/build.log
	exit 1
fi
# 送る PR は「六本とも obj/ipc/ipc.ipc_path_manager.o を繋ぐ」と書いている。
# GUI 四本は DEEP で測るが、この二本はここで建っているので、そのまま見る。
# ipc.gyp の target 'ipc' は unix_ipc.cc と ipc_path_manager.cc を両方持つ
# 一つの static_library なので、片方を繋いでいれば両方繋いでいる。
echo "--- この二本は ipc_path_manager.o を繋ぐか ---"
for p in mozc-server226 mozc-elisp226; do
	d=/usr/pkgsrc/inputmethod/$p
	o=$(find $d/work -name 'ipc.ipc_path_manager.o' 2>/dev/null | head -1)
	printf "  %-16s %s\n" "$p" "${o:+あり}${o:-なし (work は片付いているかもしれない)}"
done

echo "--- 依存として mozc-server226 を先に建てたか ---"
grep -n 'mozc-server226\|Installing binary package of mozc-server' /tmp/build.log | head -5 | sed 's/^/  /'
echo "--- X11 を引いていないか (引いていれば gtk2 や qt5 が出る) ---"
grep -ciE 'gtk2|qt5-qtbase|zinnia|/usr/X11R7' /tmp/build.log

echo
echo "##### 4. 出来たもの #####"
pkg_info | grep -iE 'mozc|emacs' | sed 's/^/  /'
for f in /usr/pkg/libexec/mozc_server /usr/pkg/bin/mozc_emacs_helper; do
	echo "--- $f ---"
	ls -l $f
	ldd $f | sed 's/^/  /'
done
for p in $(pkg_info -e 'mozc-server-*') $(pkg_info -e '*mozc-elisp-*'); do
	echo "--- $p が記録した実行時依存 (@pkgdep) ---"
	pkg_info -B "$p" >/dev/null 2>&1
	pkg_info -n "$p" 2>/dev/null | sed 's/^/  /'
done

echo
echo "##### 5. 実際に打てるか #####"
# helper の protocol を直に叩く。n i h o n g o を送って preedit を見る。
# emacs を介さないぶん、出力がそのまま引用できる。
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
id mozctest >/dev/null 2>&1 || useradd -m -s /bin/sh mozctest
MH=$(getent passwd mozctest 2>/dev/null | cut -d: -f6)
[ -n "$MH" ] || MH=/home/mozctest
# useradd -m は home を作るだけで .config は作らない。profile が無いと
# mozc_server は
#   system_util   User profile directory doesn't exist
#   process_mutex open() failed
#   mozc_server.cc  "Mozc Server is already running"   <- 誤報
# と進んで早期に Finalize へ抜け、FinalizeSingletons で null を踏む。
# 起動しないのも落ちるのも、元はここである。
mkdir -p "$MH/prof/mozc"
chown -R mozctest "$MH"
echo "  mozctest の home: $MH  ($(ls -ld "$MH" | awk '{print $1, $3}'))"

# 鍵の並びはファイルに置く。server は daemon 化して stdout を握るので、
# printf からの pipe ではなくファイルを stdin にする。
cat > /tmp/keys.txt <<'EOT'
(1 CreateSession)
(2 SendKey 1 110)
(3 SendKey 1 105)
(4 SendKey 1 104)
(5 SendKey 1 111)
(6 SendKey 1 110)
(7 SendKey 1 103)
(8 SendKey 1 111)
EOT
chmod 644 /tmp/keys.txt

# 変換が落ちたとき、同じ応答になる原因が複数ある。三つ目の
#   「server の照合に失敗している」  ipc_path_manager.cc
# は、当て物が sysctl KERN_PROC_PATHNAME で server の path を取る形なので、
# その sysctl がこの箱で効くことが前提になる。効かない箱で落ちたのか、
# 当て物が効いていないのかは、応答だけでは区別できない。
#
# 送る PR の三つ目の欠陥がこの MIB そのものである以上、手元で一度測った
# だけでは足りない。PR に書く証拠を作っているのはこの CI なので、ここで
# 測り直す。四要素であること、KERN_PROC_ARGV ではなく PATHNAME であること、
# 返る長さが終端の NUL を数えていることの三つを見る。
# (ci/netbsd-mozc334.sh が先にやっていた。同じ形を借りている。)
cat > /tmp/mib.c <<'EOT'
#include <sys/param.h>
#include <sys/sysctl.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
int main(void) {
  pid_t pid = getpid();
  char buf[1024];
  size_t len;
  int rc;

  int n3[] = { CTL_KERN, KERN_PROC_ARGS, (int)pid };
  len = sizeof(buf);
  rc = sysctl(n3, 3, buf, &len, NULL, 0);
  printf("3 要素 {CTL_KERN,KERN_PROC_ARGS,pid}      rc=%d errno=%s\n",
         rc, rc < 0 ? strerror(errno) : "-");

  int nv[] = { CTL_KERN, KERN_PROC_ARGS, (int)pid, KERN_PROC_ARGV };
  len = 0;
  rc = sysctl(nv, 4, NULL, &len, NULL, 0);
  printf("4 要素 ARGV      大きさ問い合わせ rc=%d len=%zu\n", rc, len);

  int np[] = { CTL_KERN, KERN_PROC_ARGS, (int)pid, KERN_PROC_PATHNAME };
  len = 0;
  rc = sysctl(np, 4, NULL, &len, NULL, 0);
  printf("4 要素 PATHNAME  大きさ問い合わせ rc=%d len=%zu\n", rc, len);
  len = sizeof(buf);
  rc = sysctl(np, 4, buf, &len, NULL, 0);
  printf("4 要素 PATHNAME  取得           rc=%d len=%zu path=\"%s\" strlen=%zu\n",
         rc, len, rc == 0 ? buf : "", rc == 0 ? strlen(buf) : (size_t)0);
  return 0;
}
EOT
echo "--- sysctl の MIB はこの箱でどうなるか ---"
if cc -o /tmp/mib /tmp/mib.c 2>/tmp/mib.err; then
	/tmp/mib | sed 's/^/  /'
	echo "  (3 要素が EINVAL、PATHNAME の len が strlen+1 なら、当て物の前提どおり)"
else
	echo "  mib.c が建たない:"; sed 's/^/    /' /tmp/mib.err
fi

# 照合はもう一段で外れる。ipc_path_manager.cc の
#
#	if (server_path.empty()) { return true; }
#
# は sysctl より手前に在るので、MIB が直っていても path が空なら比較は
# 走らず、それでも変換は通る。「変換が通った」ことは「比較が通った」ことを
# 意味しない。空でないことを別に見る必要がある。
#
# 空でないのは patch-config.bzl が @PREFIX@/libexec を
# LINUX_MOZC_SERVER_DIRECTORY に入れ、patch-base_base.gyp が
# MOZC_SERVER_DIRECTORY として渡し、patch-base_system__util.cc が
# それを返すからで、結果は binary に焼かれる。焼かれているかを見る。
# (netbsd-i386-24 が 2.29 で先にやっていた。同じ手を借りている。)
echo "--- server_path は空でないか (IsValidServer の二つ目の早期 return) ---"
# strings では見えない。"/usr/pkg/libexec" はちょうど 16 文字なので、
# std::string の小文字列最適化で literal にならず、8 バイトの即値二つとして
# コードに埋まる。生バイト列にも連続しては現れない。objdump で見る。
#   movabs $0x676b702f7273752f  "/usr/pkg"
#   movabs $0x6365786562696c2f  "/libexec"
if command -v objdump >/dev/null 2>&1; then
	for f in /usr/pkg/bin/mozc_emacs_helper /usr/pkg/libexec/mozc_server; do
		n=$(objdump -d "$f" 2>/dev/null \
			| grep -c '0x676b702f7273752f')
		m=$(objdump -d "$f" 2>/dev/null \
			| grep -c '0x6365786562696c2f')
		if [ "${n:-0}" -gt 0 ] && [ "${m:-0}" -gt 0 ]; then
			echo "  $f  /usr/pkg が $n 箇所、/libexec が $m 箇所 -- 空でない"
		else
			echo "  $f  見つからない (/usr/pkg=$n /libexec=$m) -- 空なら比較は走らない"
		fi
	done
else
	echo "  objdump が無いので測れない"
fi

echo "--- 参考: root で叩くと (RunLevel::DENY で拒まれる) ---"
timeout 60 /usr/pkg/bin/mozc_emacs_helper < /tmp/keys.txt > /tmp/conv-root.out 2>&1 || true
tail -1 /tmp/conv-root.out | cut -c1-120 | sed 's/^/  /'

echo "--- 一般ユーザで叩く ---"
su - mozctest -c "env XDG_CONFIG_HOME=$MH/prof timeout 60 /usr/pkg/bin/mozc_emacs_helper < /tmp/keys.txt" \
	> /tmp/conv.out 2>&1 || true
head -2 /tmp/conv.out | cut -c1-120 | sed 's/^/  /'
if grep -q 'にほんご' /tmp/conv.out; then
	echo 'RESULT 変換: にほんご が出た'
	grep -o '(value . "[^"]*")' /tmp/conv.out | tail -4 | sed 's/^/  /'
else
	echo 'RESULT 変換: にほんご が出ない'
	cut -c1-160 /tmp/conv.out | sed 's/^/  /'
	echo "  --- mozc の log ---"
	find "$MH/prof" -name '*.log' 2>/dev/null | while read f; do
		echo "  == $f"; tail -20 "$f" | sed 's/^/    /'
	done
	# 226 は MOZC_NO_LOGGING で建つので log は出ない。core の有無で
	# 「起動して落ちた」と「そもそも起動していない」を分ける。
	echo "  --- core ---"
	found=no
	for c in "$MH"/*core* /*core* /var/tmp/*core*; do
		[ -f "$c" ] || continue
		found=yes
		ls -l "$c" | sed 's/^/    /'
		# INSTALL_PROGRAM は -s で入れるので、bt は work の未 strip を使う。
		B=$(find /usr/pkgsrc/inputmethod/mozc-server226/work \
			/usr/pkgsrc/inputmethod/mozc-server226/work \
			-name mozc_server -type f -path '*out_bsd/Release*' 2>/dev/null | head -1)
		[ -n "$B" ] || B=/usr/pkg/libexec/mozc_server
		echo "    (bt は $B から)"
		gdb -batch -ex 'set pagination off' -ex bt "$B" "$c" 2>&1 | head -20 | sed 's/^/    /'
	done
	[ "$found" = yes ] || echo "    core は無い = server が起動していない"

	# helper 越しだと Session failed しか見えない。server を直に起こすと
	# stderr が読める。MOZC_NO_LOGGING で log は出ないが stderr は別。
	echo "  --- server を直に起こす ---"
	echo "    profile ($MH/prof/mozc):"
	ls -la "$MH/prof" "$MH/prof/mozc" 2>&1 | sed 's/^/      /' | head -20
	su - mozctest -c "env XDG_CONFIG_HOME=$MH/prof /usr/pkg/libexec/mozc_server" \
		> /tmp/srv.out 2>&1 &
	srvpid=$!
	sleep 10
	kill $srvpid 2>/dev/null || true
	echo "    stderr:"
	head -25 /tmp/srv.out | sed 's/^/      /'
	[ -s /tmp/srv.out ] || echo "      (何も出ない)"
	echo "    起こしたあとの socket:"
	ls -a /tmp | grep '^\.mozc\.' | sed 's/^/      /' || echo "      (無い)"
	echo "    ktrace で exec を見る:"
	su - mozctest -c "cd /tmp && env XDG_CONFIG_HOME=$MH/prof ktrace -i -f /tmp/kt.out /usr/pkg/libexec/mozc_server" \
		>/dev/null 2>&1 &
	sleep 8; pkill -f 'libexec/mozc_server' 2>/dev/null || true
	kdump -f /tmp/kt.out 2>/dev/null | grep -E 'NAMI|RET.*-1|CALL  exit' | head -15 \
		| sed 's/^/      /' || echo "      (kdump 取れず)"
fi
# profile が無いとどうなるか。server を直に起こすと profile が無くても
# 動いて socket も作るので、要求しているのは helper が server を起こす経路の
# 方だと当たりを付けている。同じ VM で profile の有無だけを変えて二度測る。
echo "--- profile が無いときはどうなるか ---"
rm -rf "$MH/prof2"; mkdir -p "$MH/prof2"; chown -R mozctest "$MH/prof2"
sudo=""
su - mozctest -c "env XDG_CONFIG_HOME=$MH/prof2 timeout 60 /usr/pkg/bin/mozc_emacs_helper < /tmp/keys.txt" \
	> /tmp/conv-noprof.out 2>&1 || true
if grep -q 'にほんご' /tmp/conv-noprof.out; then
	echo "  mozc/ が無くても打てた (helper か server が自分で作る)"
else
	echo "  mozc/ が無いと打てない"
	tail -1 /tmp/conv-noprof.out | cut -c1-90 | sed 's/^/    /'
fi
echo "    そのあと mozc/ は出来たか: $(ls -d "$MH/prof2/mozc" 2>/dev/null || echo '出来ていない')"

# 上は XDG_CONFIG_HOME 自体は在って mozc/ だけ無い場合。i386 で落ちたのは
# XDG_CONFIG_HOME に指した .config そのものが無い場合だったので、そちらも
# 測る。useradd -m は .config を作らないから、新しい account では普通に
# 起きる。ここで落ちるなら、server が無いときと root のときに続いて三つ目の
# 「同じ session-error が出る別の原因」になる。
echo "--- XDG_CONFIG_HOME 自体が無いときはどうなるか ---"
rm -rf "$MH/prof3"
su - mozctest -c "env XDG_CONFIG_HOME=$MH/prof3/.config timeout 60 /usr/pkg/bin/mozc_emacs_helper < /tmp/keys.txt" \
	> /tmp/conv-noxdg.out 2>&1 || true
if grep -q 'にほんご' /tmp/conv-noxdg.out; then
	echo "  RESULT XDG_CONFIG_HOME が無くても打てた (自分で mkdir -p する)"
else
	echo "  RESULT XDG_CONFIG_HOME が無いと打てない -- 四つ目の原因"
	tail -1 /tmp/conv-noxdg.out | cut -c1-90 | sed 's/^/    /'
fi
echo "    そのあと出来たか: $(ls -d "$MH/prof3/.config/mozc" 2>/dev/null || echo '出来ていない')"

echo "--- 変換候補に 日本語 があるか ---"
if grep -q '日本語' /tmp/conv.out; then echo '  ある'; else echo '  ない'; fi

# socket の名前。NetBSD の sockaddr_un は sun_family の手前に 1 バイトの
# sun_len を持つので、sizeof(sun_family) では offsetof に 1 足りず、path の
# 末尾が落ちて .session が .sessio になっていた。直っていれば .session。
echo "--- socket の名前 ---"
ls -a /tmp | grep '^\.mozc\.' | sed 's/^/  /' || echo "  (無い)"
n_ok=$(ls -a /tmp | grep -c '\.session$' || true)
n_ng=$(ls -a /tmp | grep -c '\.sessio$' || true)
echo "  .session で終わるもの: $n_ok"
echo "  .sessio  で終わるもの: $n_ng   (0 でなければ当て物が効いていない)"

echo
# 送る PR の一つ目の主張。server を退けると CreateSession は通り、
# 最初の SendKey で落ちる。「入っているように見えて最初の一打で駄目」の
# 実物がこれなので、引用する以上ここで取る。
echo "--- server を退けると何が返るか (依存が要る理由) ---"
pkill -f '/usr/pkg/libexec/mozc_server' 2>/dev/null || true
sleep 1
rm -f /tmp/.mozc.*
if mv /usr/pkg/libexec/mozc_server /root/mozc_server.hidden 2>/dev/null; then
	su - mozctest -c "env XDG_CONFIG_HOME=$MH/prof sh -c \
		\"printf '(1 CreateSession)\n(2 SendKey 1 97)\n' | timeout 30 /usr/pkg/bin/mozc_emacs_helper\"" \
		> /tmp/noserver.out 2>&1 || true
	grep -E 'emacs-session-id|session-error' /tmp/noserver.out | sed 's/^/  /'
	mv /root/mozc_server.hidden /usr/pkg/libexec/mozc_server
	echo "  server を戻した: $(ls -l /usr/pkg/libexec/mozc_server | awk '{print $5}') バイト"
else
	echo "  ★ server を退けられない"
fi

if [ "$DEEP" = 1 ] && [ -s /root/mozc_server.unpatched ]; then
	# 二つ目の主張。socket 名が変わるので、直す前の server と直した後の
	# helper は出会えない。退避した未修正 binary を直に起こして対にする。
	echo "--- (DEEP) 直す前の server と直した後の helper を対にする ---"
	pkill -f 'mozc_server' 2>/dev/null || true
	sleep 1
	rm -f /tmp/.mozc.*
	cp /root/mozc_server.unpatched /tmp/mozc_server.old
	chmod 755 /tmp/mozc_server.old; chown mozctest /tmp/mozc_server.old
	su - mozctest -c "env XDG_CONFIG_HOME=$MH/prof /tmp/mozc_server.old" \
		> /tmp/oldsrv.out 2>&1 &
	sleep 8
	# 腕が違うことを先に示す。古い server は名前を一文字切るので .sessio を
	# 作るはずで、.session が出たなら退避した binary が未修正ではない。
	# 対の結果は session-error で主張どおりに見えるが、/tmp から起こした
	# server が path 照合に落ちただけ、という別の理由でもそうなる。
	sock=$(ls -a /tmp | grep '^\.mozc\.' | head -1)
	echo "  古い server が作った socket: ${sock:-(無し)}"
	case "$sock" in
	*.sessio) echo "  測定は成立している (名前が一文字切れている)" ;;
	*.session) echo "  ★ 測定が成立していない -- 退避した binary が未修正でない"
	           echo "  ★ 以下の結果は使えない" ;;
	*)         echo "  ★ 測定が成立していない -- socket が無い" ;;
	esac
	su - mozctest -c "env XDG_CONFIG_HOME=$MH/prof sh -c \
		\"printf '(1 CreateSession)\n(2 SendKey 1 97)\n' | timeout 30 /usr/pkg/bin/mozc_emacs_helper\"" \
		> /tmp/pair.out 2>&1 || true
	echo "  新しい helper の返り:"
	grep -E 'emacs-session-id|session-error' /tmp/pair.out | sed 's/^/    /' \
		|| tail -2 /tmp/pair.out | sed 's/^/    /'
	pkill -f 'mozc_server.old' 2>/dev/null || true
	rm -f /tmp/mozc_server.old /tmp/.mozc.*
fi

if [ "$DEEP" = 1 ] && [ "$DEEP_GUI" = 1 ]; then
	# 三つ目と四つ目の主張。PATCHDIR は共有なので当て物は六本に効く。
	# 四本とも建つこと、ipc_path_manager.o を繋ぐこと、mozc-tool226 が
	# Qt を保ったままであることを測る。
	echo "--- (DEEP) GUI を切らない四本を建てる ---"
	for p in mozc-tool226 mozc-renderer226 ibus-mozc226 uim-mozc226; do
		cd /usr/pkgsrc/inputmethod/$p
		printf "  %-18s " "$p"
		if make build > /tmp/b-$p.log 2>&1; then
			o=$(find work -name 'ipc.ipc_path_manager.o' 2>/dev/null | head -1)
			q=$(grep -c 'use_qt=NO' /tmp/b-$p.log || true)
			printf "建った  ipc_path_manager.o=%s  use_qt=NO の回数=%s\n" \
				"$([ -n "$o" ] && echo あり || echo なし)" "$q"
		else
			echo "★ 建たない"
			df -h / | sed 's/^/      /'
			grep -nE 'No space|Error code|error:|cannot|failed' /tmp/b-$p.log \
				| tail -25 | sed 's/^/      /'
		fi
	done
	echo "  --- 当て物が木に入っているか (四本とも) ---"
	for p in mozc-tool226 mozc-renderer226 ibus-mozc226 uim-mozc226; do
		d=/usr/pkgsrc/inputmethod/$p/work/mozc-2.26.4282.100/src
		printf "    %-18s offsetof=%s KERN_PROC_PATHNAME=%s\n" "$p" \
			"$(grep -c offsetof $d/ipc/unix_ipc.cc 2>/dev/null || echo -)" \
			"$(grep -c KERN_PROC_PATHNAME $d/ipc/ipc_path_manager.cc 2>/dev/null || echo -)"
	done
	echo "  --- mozc-tool226 は Qt のオブジェクトを持つか ---"
	find /usr/pkgsrc/inputmethod/mozc-tool226/work -name '*.o' -path '*gui*' 2>/dev/null \
		| wc -l | sed 's/^/    gui の .o /'
fi

echo
echo "##### 6. Emacs から見えるか #####"
# mozc.elc が入っていること、(require 'mozc) で japanese-mozc が
# input-method-alist に載ることを見る。emacs の版ごとに変わりうるのは
# ここだけで、helper と server は版に依らない。
ls -l /usr/pkg/share/emacs/site-lisp/mozc.el* | sed 's/^/  /'
/usr/pkg/bin/emacs --version | head -1 | sed 's/^/  /'
/usr/pkg/bin/emacs -Q -batch -L /usr/pkg/share/emacs/site-lisp \
	--eval '(progn
		  (require (quote mozc))
		  (message "japanese-mozc: %s"
			   (if (assoc "japanese-mozc" input-method-alist) "登録された" "無い"))
		  (message "mozc-mode: %s" (if (fboundp (quote mozc-mode)) "ある" "無い")))' \
	2>&1 | sed 's/^/  /'
GUEST
