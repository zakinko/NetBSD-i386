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

$SSH "OVERLAY='$OVERLAY' ETYPE='$ETYPE' sh -s" <<'GUEST'
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

echo "=== overlay を被せる ==="
cd /tmp
ftp -o overlay.tar.gz "$OVERLAY"
tar xzf overlay.tar.gz
rm -rf /usr/pkgsrc/zakinko
mv pkgsrc-zakinko-main /usr/pkgsrc/zakinko
ls -d /usr/pkgsrc/zakinko/mozc-server226 /usr/pkgsrc/zakinko/mozc-elisp226

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
echo "##### 2. MOZC_NO_GUI を書かない四つは変わらないか #####"
# 手元と同じ測り方。patched な Makefile.common を読む写しを作り、本家側と
# make show-all を突き合わせる。package の path だけ揃えて diff を取る。
for p in ibus-mozc226 mozc-renderer226 mozc-tool226 uim-mozc226; do
	rm -rf /usr/pkgsrc/zakinko/chk-$p
	cp -R /usr/pkgsrc/inputmethod/$p /usr/pkgsrc/zakinko/chk-$p
	sed -e 's,\.\./\.\./inputmethod/mozc-server226/Makefile.common,../../zakinko/mozc-server226/Makefile.common,' \
	    /usr/pkgsrc/zakinko/chk-$p/Makefile > /tmp/m && mv /tmp/m /usr/pkgsrc/zakinko/chk-$p/Makefile
	( cd /usr/pkgsrc/inputmethod/$p && make show-all 2>/dev/null ) | sed "s,inputmethod/$p,PKG,g" > /tmp/a
	( cd /usr/pkgsrc/zakinko/chk-$p    && make show-all 2>/dev/null ) | sed "s,zakinko/chk-$p,PKG,g" > /tmp/b
	n=$(wc -l < /tmp/a); d=$(diff /tmp/a /tmp/b | grep -c '^[<>]' || true)
	printf '  %-18s %5s 行中 差 %s 行\n' "$p" "$n" "$d"
	[ "$d" = "0" ] || diff /tmp/a /tmp/b | grep '^[<>]' | head -10
	rm -rf /usr/pkgsrc/zakinko/chk-$p
done

echo
echo "##### 3. 直した mozc-elisp226 を建てる #####"
cd /usr/pkgsrc/zakinko/mozc-elisp226
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
mkdir -p "$MH/prof"
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
fi
echo "--- 変換候補に 日本語 があるか ---"
if grep -q '日本語' /tmp/conv.out; then echo '  ある'; else echo '  ない'; fi

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
