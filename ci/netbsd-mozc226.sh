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
#   3. MOZC_NO_GUI を書かない他の四つが何も変わらないこと
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
MEM=${MEM:-8192} DIR=. sh runvm.sh "$NAME" "$PORT"
trap cleanup EXIT INT TERM

# 送る diff そのものを VM へ入れる。overlay の写しではなく、これを当てて
# 建てる。写しは zakinko/ に置くので ${PKGPATH} が変わり、PKGPATH で分ける
# 仕掛けを手元では確かめられない。VM の中なら本来の path で試せる。
DIFF=${DIFF:-$SRCROOT/doc/upstream/pr/mozc-elisp226.diff}
[ -f "$DIFF" ] || { echo "$0: $DIFF が無い" >&2; exit 1; }
echo "=== 送る diff を入れる: $DIFF ($(wc -l < "$DIFF") 行) ==="
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o LogLevel=ERROR -i "$WORK/$NAME.id" -P "$PORT" \
    "$DIFF" root@127.0.0.1:/tmp/mozc226.diff

$SSH "ETYPE='$ETYPE' sh -s" <<'GUEST'
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
	env PKG_PATH="$BINPKG" pkg_add -U "$p" 2>&1 | grep -vE '^$' | head -2 | sed "s/^/    $p: /"
	pkg_info -e "$p" >/dev/null 2>&1 || echo "  !! $p は binary で入らなかった (ソースから建てることになる)"
done
unset PKG_PATH
pkg_info | egrep -i 'gmake|ninja|gyp|six|python|emacs' | sed 's/^/  /'
df -h / | sed 's/^/  /'

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
echo "  物理: $(sysctl -n hw.physmem64 2>/dev/null || sysctl -n hw.physmem)"
if [ "$(swapctl -l 2>/dev/null | grep -c /)" = "0" ]; then
	dd if=/dev/zero of=/var/tmp/swapfile bs=1m count=4096 2>/dev/null
	chmod 600 /var/tmp/swapfile
	swapctl -a /var/tmp/swapfile && echo "  swap を 4G 足した"
fi
swapctl -l 2>/dev/null | sed 's/^/  /'
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
tail -12 /etc/mk.conf | sed 's/^/  /'

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
