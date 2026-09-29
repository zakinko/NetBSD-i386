#!/bin/sh
# freebsd/freebsd-src#2420 (printf-pos.c が位置指定の %F に型を付けない) の
# 直しと試験を、FreeBSD 15.1 の上で前後に分けて測る。
#
# 直す file (printf-pos.c, snprintf_test.c, swprintf_test.c) と、それを使う
# vfprintf.c / vfwprintf.c は releng/15.1 と main で一字も違わない
# (2026-09-29 に git diff で確認)。なので 15.1 の source に当てて測れば、
# main の code を測ったことになる。
#
#   1. 素の libc で、新しい試験を含む snprintf_test / swprintf_test を回す
#      -> *_F だけ落ちるはず
#   2. 入っている /usr/tests/lib/libc/stdio を Kyua で回して基準を控える
#   3. 直した libc を建てて入れる (使い捨ての VM)
#   4. 同じ物を回す -> 全部通り、Kyua の結果が基準と同じはず
set -eu
D=$(cd "$(dirname "$0")" && pwd)
W=/var/tmp/pf
rm -rf "$W"; mkdir -p "$W"
uname -a

echo "=== 15.1 の source"
fetch -q -o "$W/src.txz" https://download.freebsd.org/releases/amd64/15.1-RELEASE/src.txz
tar -C / -xf "$W/src.txz"
cd /usr/src
for p in "$D"/0*.patch; do
	echo "--- $(basename "$p")"
	patch -p1 -f -F0 -i "$p" </dev/null
done
grep -c "case 'F':" lib/libc/stdio/printf-pos.c | sed 's/^/printf-pos.c の case F: /'

echo "=== 試験を木の make で建てる"
cd /usr/src/lib/libc/tests/stdio
make obj >"$W/tests-build.log" 2>&1 && make snprintf_test swprintf_test >>"$W/tests-build.log" 2>&1 \
	|| { echo "NG: 試験が建たない"; tail -60 "$W/tests-build.log"; exit 1; }
OBJ=$(make -V .OBJDIR)
ls -l "$OBJ/snprintf_test" "$OBJ/swprintf_test"

cases() {
	for prog in snprintf_test swprintf_test; do
		for tc in $("$OBJ/$prog" -l | awk '/^ident:/{print $2}'); do
			if "$OBJ/$prog" "$tc" >"$W/$prog.$tc.$1.out" 2>&1; then
				r=PASS
			else
				r=FAIL
			fi
			printf '%-7s %-15s %-14s %s\n' "$1" "$prog" "$tc" "$r" | tee -a "$W/cases.$1"
		done
	done
}

kyua_counts() {
	cd /usr/tests/lib/libc/stdio
	kyua test >/dev/null 2>&1 || true
	# --verbose は通った case を並べないので、--results-filter で全部を出させる。
	# 結果は "prog:case  ->  passed  [0.004s]" の形で、-> の後ろは空白二つ
	kyua report --results-filter passed,skipped,xfail,broken,failed >"$W/kyua-raw.$1" 2>&1
	grep -E '^[a-z_0-9]+:[A-Za-z_0-9]+  ->  ' "$W/kyua-raw.$1" | sed 's/  \[.*//; s/:  *[^ ].*//' | awk '{print $1, $3}' | sort > "$W/kyua.$1"
	echo "Kyua ($1): $(wc -l <"$W/kyua.$1" | tr -d ' ') 件、passed $(awk '$2 == "passed"' "$W/kyua.$1" | wc -l | tr -d ' ')"
	awk '$2 != "passed" && $2 != "skipped"' "$W/kyua.$1" | sed 's/^/  /'
	grep -E '^Test cases:' "$W/kyua-raw.$1"
}

echo "=== 1. 素の libc"
LIBC_BEFORE=$(sha256 -q /lib/libc.so.7)
cases before
echo "--- 落ちた case の中身"
for f in "$W"/*.before.out; do
	case "$f" in *_F.before.out) echo "## $(basename "$f")"; cat "$f";; esac
done
kyua_counts before

echo "=== 3. 直した libc を建てて入れる"
cd /usr/src/lib/libc
{ make -j4 obj && make -j4 all && make install; } >"$W/libc-build.log" 2>&1 \
	|| { echo "NG: libc が建たない"; grep -nE 'error|Error|\*\*\*' "$W/libc-build.log" | head -20; tail -40 "$W/libc-build.log"; exit 1; }
LIBC_AFTER=$(sha256 -q /lib/libc.so.7)
echo "libc.so.7: 前 ${LIBC_BEFORE%${LIBC_BEFORE#????????????}}  後 ${LIBC_AFTER%${LIBC_AFTER#????????????}}"
[ "$LIBC_BEFORE" != "$LIBC_AFTER" ] || { echo "libc が入れ替わっていない"; exit 1; }
ldd "$OBJ/snprintf_test" | grep libc

echo "=== 4. 直した libc"
cases after
kyua_counts after

echo "=== 前後の比較"
paste -d' ' "$W"/kyua.before "$W"/kyua.after | awk '{ if ($2 != $4) print "変わった: " $0 }'
cmp -s "$W/kyua.before" "$W/kyua.after" && echo "Kyua の結果は前後で同じ"

# 期待: 前は *_F だけ落ち、後は全部通る。一つでも外れたら落とす
bad=0
awk '$4 == "FAIL" && $3 !~ /_F$/' "$W/cases.before" | grep . && { echo "NG: 素の libc で F 以外が落ちた"; bad=1; }
[ "$(awk '$3 ~ /_F$/ && $4 == "FAIL"' "$W/cases.before" | wc -l)" -eq 2 ] || { echo "NG: 素の libc で *_F が二つとも落ちていない (試験が bug を捕まえていない)"; bad=1; }
awk '$4 == "FAIL"' "$W/cases.after" | grep . && { echo "NG: 直した libc で落ちた case がある"; bad=1; }
cmp -s "$W/kyua.before" "$W/kyua.after" || { echo "NG: Kyua の結果が前後で違う"; bad=1; }
[ "$bad" = 0 ] && echo "RESULT OK: 前は snprintf_F と swprintf_F だけ落ち、後は全部通り、Kyua は前後で同じ"
echo "=== 例の program"
cat > "$W/demo.c" <<'C'
#include <math.h>
#include <stdio.h>
int main(void) {
	printf("[%1$F]\n", -INFINITY);
	printf("[%1$F]\n", 1.5);
	printf("[%F]\n", 1.5);
	printf("%d\n", snprintf(NULL, 0, "%1$*2$F", 1.5, 10));
	return 0;
}
C
cc -o "$W/demo" "$W/demo.c" && "$W/demo"
exit "$bad"
