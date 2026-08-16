#!/bin/sh
#
# NetBSD/i386 の実機で -Wformat が何を言うかを見る。
#
#	sh ci/netbsd-i386-format.sh [イメージ名]
#	例: sh ci/netbsd-i386-format.sh i386-11.0
#
# src/augtool.c と examples/dump.c はミリ秒の値を time_t に入れて %ld で
# 表示している。long が 32bit で time_t が 64bit の環境では誤りだが、
# 手元の pkgsrc には既に当て物が入っているので、build.yml では警告の出る
# 状態を作れない。ここでは pkgsrc を通さず、素の五行を直に組む。
#
# イメージは netbsd-ci-images の release から落とす。起動と停止はあちらの
# スクリプトをそのまま使う。同じことを二箇所に書くと必ず片方が古くなる。

set -eu

NAME=${1:-i386-11.0}
IMGREPO=${IMGREPO:-zakinko/netbsd-ci-images}
IMGTAG=${IMGTAG:-images}
IMGREF=${IMGREF:-main}
PORT=${PORT:-2223}
WORK=${WORK:-$PWD/.vm-format}

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

echo "=== 素性 ==="
$SSH 'uname -a; cc --version 2>/dev/null | head -1 || gcc --version | head -1'

echo "=== 幅と警告 ==="
$SSH sh -s <<'GUEST'
set -e
cd /tmp

cat > w.c <<'EOF'
#include <stdio.h>
#include <time.h>
int main(void) {
    printf("long=%zu time_t=%zu\n", sizeof(long), sizeof(time_t));
    return 0;
}
EOF
cc -o w w.c && ./w

# augtool.c の print_time_taken() をそのまま写したもの。
cat > t.c <<'EOF'
#include <stdio.h>
#include <sys/time.h>
void print_time_taken(const struct timeval *start, const struct timeval *stop) {
    time_t elapsed = (stop->tv_sec - start->tv_sec)*1000
                   + (stop->tv_usec - start->tv_usec)/1000;
    printf("Time: %ld ms\n", elapsed);
}
EOF

# 当て物をしたあとの形。time_t ではなく long long にする。elapsed は
# 時刻ではなく経過時間なので、time_t を使っているのがそもそも誤りである。
sed -e 's|time_t elapsed|long long elapsed|' -e 's|%ld ms|%lld ms|' t.c > t2.c

echo '--- いまのコード (%ld) ---'
cc -Wall -Wformat -c -o t.o t.c 2>&1 | head -10
echo '--- 直したあと ((long long) つき) ---'
cc -Wall -Wformat -c -o t2.o t2.c 2>&1 | head -10
echo '  (直したあとに何も出なければ警告なし)'

# 警告が消えることと、正しい値が出ることは別である。実際に何が出るかを
# 見る。i386 の varargs は 64bit 値をスタックに積むので、%ld が下位 32bit
# を読むだけなら小さい値では化けない。それなら「値が壊れる」とは書けない。
echo '--- 実際に何が表示されるか ---'
cat > r.c <<'EOF'
#include <stdio.h>
#include <time.h>
int main(void) {
    time_t v[] = { 1234, 4294967296LL, 5000000000LL, -1 };
    unsigned i;
    for (i = 0; i < sizeof(v)/sizeof(v[0]); i++) {
        printf("  期待 %lld\n", (long long) v[i]);
        printf("    time_t + %%ld    -> ");
        printf("%ld\n", v[i]);
        printf("    long long + %%lld -> ");
        { long long e = v[i]; printf("%lld\n", e); }
    }
    return 0;
}
EOF
cc -Wall -o r r.c 2>/dev/null || cc -o r r.c
./r
GUEST
