#!/bin/sh
# XEmacs 21.4 で、外から来た大きさを alloca していた五箇所が落ちること、
# 当て物で落ちなくなることを見る。
#
# 手元で測れたのは NetBSD 10.1/i386 の一台きりだった。送るときに
# 「こちらでは落ちます」だけでは弱いので、誰でも開ける run を足す。
#
# 五つとも、渡す大きさを Lisp 側が決める:
#
#	doprnt.c      (format "%3000000d" 1)            32 + 幅/精度
#	print.c       (princ (make-string 3000000 ?x))  印字対象の長さ
#	editfns.c     (format-time-string <長い>)       書式の長さ×6+50
#	search.c      (regexp-quote <長い>)             引数の長さ×2
#	casefiddle.c  (upcase <長い>)                   長さ×MAX_EMCHAR_LEN
#
# alloca は「スタックが足りない」を返せないので、そのまま踏み抜く。
# NetBSD/i386 では soft limit が 2048KB で、三メガの alloca が越えた。
# 箱によって limit は違うので、ここでは ulimit を明示して揃える。
#
# 21.4 は unexec ではなく --pdump で建てる。ASLR の効いた箱で unexec は
# 通らないが、pdump なら関係ない。
#
# 使い方: alloca.sh <21.4 の checkout> <base|patched>

set -e
SRC=$1
WHICH=$2
[ -n "$SRC" ] && [ -n "$WHICH" ] || { echo "usage: $0 <checkout> <base|patched>" >&2; exit 2; }

cd "$SRC"
case "$WHICH" in
  base)    REV=59c6ed7d ;;   # 上流 tip。当て物の親
  patched) REV=cb5c8dd6 ;;   # その上に四本
  *) echo "base か patched" >&2; exit 2 ;;
esac
git checkout -f "$REV" >/dev/null 2>&1 || { echo "!! $REV を checkout できない" >&2; exit 3; }
echo "== $WHICH = $(git log --oneline -1) =="

CFLAGS="-O2 -Dunix -DTERMINFO" \
./configure --prefix="$PWD/_inst" --with-x11=no --with-mule=yes \
    --with-clash-detection --pdump --with-system-malloc \
    --with-msw=no --with-postgresql=no --with-sound=none > conf.log 2>&1 || {
  echo "!! configure が落ちた"; tail -20 conf.log; exit 4; }
make -j2 > make.log 2>&1 || { echo "!! make が落ちた"; tail -25 make.log; exit 5; }
make install > inst.log 2>&1 || true      # man の段だけ落ちることがある
X="$PWD/_inst/bin/xemacs"
[ -x "$X" ] || { echo "!! xemacs が入っていない"; tail -10 inst.log; exit 6; }
"$X" -batch -vanilla -eval '(princ (emacs-version))' | head -1

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/b1.el" <<'Z'
(progn (format "%3000000d" 1) (princ "survived\n"))
Z
cat > "$T/b2.el" <<'Z'
(progn (princ (make-string 3000000 ?x)) (princ "\nsurvived\n"))
Z
cat > "$T/b3.el" <<'Z'
(progn (format-time-string (make-string 500000 ?a)) (princ "survived\n"))
Z
cat > "$T/b4.el" <<'Z'
(progn (regexp-quote (make-string 3000000 ?x)) (princ "survived\n"))
Z
cat > "$T/b5.el" <<'Z'
(progn (upcase (make-string 3000000 ?x)) (princ "survived\n"))
Z

echo "== make-temp-file =="
"$X" -batch -vanilla -eval '(princ (format "fboundp=%s\n" (fboundp (quote make-temp-file))))'

echo "== 五式 (ulimit -s 2048 に揃える) =="
fell=0
for t in b1 b2 b3 b4 b5; do
  ( ulimit -s 2048 2>/dev/null
    "$X" -batch -vanilla -load "$T/$t.el" >/dev/null 2>&1 ) && rc=0 || rc=$?
  case $rc in
    0)   echo "  $t: 生存" ;;
    139) echo "  $t: SIGSEGV"; fell=$((fell+1)) ;;
    *)   echo "  $t: rc=$rc" ;;
  esac
done

if [ "$WHICH" = patched ]; then
  [ "$fell" = 0 ] || { echo "!! 当て物を入れたのに $fell 個落ちた"; exit 1; }
  echo "=> patched: 五つとも生存"
else
  [ "$fell" = 5 ] || { echo "!! 素の木で落ちたのは $fell 個。五つ落ちる想定"; exit 1; }
  echo "=> base: 五つとも落ちる (想定どおり)"
fi
