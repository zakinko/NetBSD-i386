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
if [ ! -d /usr/pkgsrc/mk ]; then
	ftp -o /tmp/pkgsrc.tar.gz http://cdn.netbsd.org/pub/pkgsrc/current/pkgsrc.tar.gz
	tar xzf /tmp/pkgsrc.tar.gz -C /usr
	rm -f /tmp/pkgsrc.tar.gz
fi
echo "  mozc-elisp226 の版: $(grep -m1 '\$NetBSD' /usr/pkgsrc/inputmethod/mozc-elisp226/Makefile)"

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
EOF
tail -8 /etc/mk.conf | sed 's/^/  /'

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
printf '(1 CreateSession)\n(2 SendKey 1 110)\n(3 SendKey 1 105)\n(4 SendKey 1 104)\n(5 SendKey 1 111)\n(6 SendKey 1 110)\n(7 SendKey 1 103)\n(8 SendKey 1 111)\n' \
	| /usr/pkg/bin/mozc_emacs_helper > /tmp/conv.out 2>&1 || true
echo "--- helper の応答 (末尾) ---"
tail -2 /tmp/conv.out | sed 's/^/  /'
if grep -q 'にほんご' /tmp/conv.out; then
	echo 'RESULT 変換: にほんご が出た'
else
	echo 'RESULT 変換: にほんご が出ない'
	cat /tmp/conv.out | sed 's/^/  /'
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
