#!/bin/sh
# freebsd/freebsd-src#2420 を FreeBSD 16.0-CURRENT の上で前後に分けて測る。
# cloud-init の runcmd から root で呼ばれる。結果は $OUT に書き、呼ぶ側が
# 専用の disk へ書き出す。
#
# source は起動した kernel と同じ commit を取る。uname -v の
# main-n<数>-<hash> の hash と、host が像の名前から引いた 40 桁が前方一致
# するのを確かめ、その tree を落とす。日付の違う src.txz だと、測った物と走っている物がずれる。
#
# 試験は patch を当てた木から lib/libc/tests/stdio を全部建てて Kyua で回す。
# 判定: 直した後に落ちる case の集合 = 直す前の集合 - {snprintf_F, swprintf_F}。
# 前の集合に snprintf_F と swprintf_F が入っていること (試験が bug を捕まえて
# いること) も確かめる。CURRENT に元から落ちる試験があっても比べられる形。
set -u
OUT=/var/tmp/result.txt
W=/var/tmp/pf
D=$1        # patch と script を置いた dir
exec >"$OUT" 2>&1
set -x
uname -a
freebsd-version -ku

H=$(uname -v | sed -n 's/.*main-n[0-9]*-\([0-9a-f]*\).*/\1/p')
[ -n "$H" ] || { echo "NG: uname -v から hash が取れない"; exit 1; }
# 40 桁は host が token 付きで引いて seed に入れてある (VM から認証なしで
# API を叩くと、共有の IP で回数の上限に当たることがある)
FULL=$(cat "$D/commit")
case "$FULL" in "$H"*) ;; *) echo "NG: 像の commit $FULL と kernel の $H が合わない"; exit 1;; esac
echo "kernel の commit: $H -> $FULL"

rm -rf "$W" /usr/src; mkdir -p "$W" /usr/src
fetch -qo "$W/src.tgz" "https://codeload.github.com/freebsd/freebsd-src/tar.gz/$FULL"
tar -C /usr/src --strip-components 1 -xzf "$W/src.tgz"
cd /usr/src || exit 1
for p in "$D"/0*.patch; do
	echo "--- $(basename "$p")"
	patch -p1 -f -F0 -i "$p" </dev/null || { echo "NG: $p が当たらない"; exit 1; }
done
grep -c "case 'F':" lib/libc/stdio/printf-pos.c

echo "=== 試験を木の make で建てる (stdio 全部)"
# stdio の試験には NetBSD 由来の物が混ざり、木の中の libnetbsd を link する
# (-lnetbsd_pie が無いと落ちる、run 36516243796)。先に建てておく
{ make -C /usr/src/lib/libnetbsd obj && make -C /usr/src/lib/libnetbsd -j4; } >"$W/libnetbsd-build.log" 2>&1 \
	|| { echo "NG: libnetbsd が建たない"; tail -40 "$W/libnetbsd-build.log"; exit 1; }
cd /usr/src/lib/libc/tests/stdio || exit 1
{ make obj && make -j4; } >"$W/tests-build.log" 2>&1 \
	|| { echo "NG: 試験が建たない"; grep -nE 'error|Error|\*\*\*' "$W/tests-build.log" | head -20; tail -60 "$W/tests-build.log"; exit 1; }
OBJ=$(make -V .OBJDIR)
ls "$OBJ"/Kyuafile "$OBJ"/snprintf_test "$OBJ"/swprintf_test || exit 1

fails() {
	# 結果の file を名指しする。kyua report は既定で「今いる dir の試験の最新の
	# 結果」を探すので、test と report を別の dir で打つと 0 件になる
	# (run 36520987443 がそうだった)
	rm -f "$W/k.$1.db"
	kyua test --results-file="$W/k.$1.db" -k "$OBJ/Kyuafile" >/dev/null 2>&1
	kyua report --results-file="$W/k.$1.db" --results-filter passed,skipped,xfail,broken,failed >"$W/report.$1" 2>&1
	grep -E '^Test cases:' "$W/report.$1"
	grep -E '^[a-z_0-9]+:[A-Za-z_0-9]+  ->  ' "$W/report.$1" | sed 's/  \[.*//' | sort >"$W/all.$1"
	grep -v -- '->  passed' "$W/all.$1" | grep -v -- '->  skipped' | awk '{print $1}' | sort >"$W/fail.$1"
	echo "Kyua ($1): $(wc -l <"$W/all.$1" | tr -d ' ') 件中、落ちた/壊れた $(wc -l <"$W/fail.$1" | tr -d ' ') 件"
	[ -s "$W/all.$1" ] || { echo "NG: Kyua の結果が 0 件 (測れていない)"; tail -20 "$W/report.$1"; exit 1; }
	sed 's/^/  落ち: /' "$W/fail.$1"
}

echo "=== 1. 素の libc"
B=$(sha256 -q /lib/libc.so.7)
fails before
for tc in snprintf_F swprintf_F; do
	p=${tc%_F}_test
	echo "## $p:$tc (素の libc)"; "$OBJ/$p" "$tc" 2>&1 | head -20
done

echo "=== 2. 直した libc を建てて入れる"
cd /usr/src/lib/libc || exit 1
# MK_TESTS=no: lib/libc で make all を打つと tests/ まで降り、木の中にしか無い
# libnetbsd を探して落ちる (run 36516236929)。要るのは libc 本体だけ
{ make -j4 obj && make -j4 MK_TESTS=no all && make MK_TESTS=no install; } >"$W/libc-build.log" 2>&1 \
	|| { echo "NG: libc が建たない"; grep -nE 'error|Error|\*\*\*' "$W/libc-build.log" | head -20; tail -40 "$W/libc-build.log"; exit 1; }
A=$(sha256 -q /lib/libc.so.7)
echo "libc.so.7: 前 $B / 後 $A"
[ "$B" != "$A" ] || { echo "NG: libc が入れ替わっていない"; exit 1; }
ldd "$OBJ/snprintf_test" | grep libc

echo "=== 3. 直した libc"
fails after

echo "=== 判定"
bad=0
grep -qx 'snprintf_test:snprintf_F' "$W/fail.before" && grep -qx 'swprintf_test:swprintf_F' "$W/fail.before" \
	|| { echo "NG: 素の libc で *_F が落ちていない (試験が bug を捕まえていない)"; bad=1; }
grep -vx -e 'snprintf_test:snprintf_F' -e 'swprintf_test:swprintf_F' "$W/fail.before" >"$W/expect.after"
cmp -s "$W/expect.after" "$W/fail.after" || { echo "NG: 直した後の落ちが期待と違う"; diff "$W/expect.after" "$W/fail.after"; bad=1; }
[ "$bad" = 0 ] && echo "RESULT OK: 素の libc では snprintf_F と swprintf_F が落ち、直した libc では通り、他の結果は前後で同じ"

echo "=== 例の program"
printf '%s\n' '#include <math.h>' '#include <stdio.h>' 'int main(void) {' \
	'printf("[%1$F]\n", -INFINITY); printf("[%1$F]\n", 1.5); printf("[%F]\n", 1.5);' \
	'printf("%d\n", snprintf(NULL, 0, "%1$*2$F", 1.5, 10)); return 0; }' >"$W/demo.c"
cc -o "$W/demo" "$W/demo.c" && "$W/demo"
echo "RC=$bad"
