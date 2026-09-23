#!/bin/sh
# FreeBSD / OpenBSD / DragonFly で pkgsrc を bootstrap し、BSD 対応の当て物を
# 入れた mozc-server を建てる。三つの OS で同じ script を走らせる。
#
# 第一引数 probe なら show-var と depends と fetch まで。build なら建てる。
set -u
STAGE=${1:-probe}
BRANCH=${2:-current}
WS=${GITHUB_WORKSPACE:-$(pwd)}

# / が小さい OS が在るので、木も work も広い所に置く。
W=""
for d in /home /usr/home /var/tmp /tmp; do
  if [ -d "$d" ] && [ -w "$d" ]; then W="$d/mozcwork"; break; fi
done
[ -n "$W" ] || W="$HOME/mozcwork"
mkdir -p "$W" || exit 1
# macOS の /var は /private/var への symlink で、pkgsrc は
# 「The path to WRKDIR ... must be canonical」で止まる。実体に直す。
W=$(cd "$W" && pwd -P)

# /usr/pkg に書けるなら慣例どおり。書けなければ作業場の下に置く
# (macOS の runner は root ではない)。
PREFIX=/usr/pkg
if ! mkdir -p "$PREFIX" 2>/dev/null; then PREFIX="$W/pkg"; mkdir -p "$PREFIX"; fi

# 取ってくる道具は OS で違う。BSD は fetch か ftp、Linux と macOS は curl。
if command -v fetch >/dev/null 2>&1; then GET="fetch -o"
elif command -v curl >/dev/null 2>&1; then GET="curl -fsSL -o"
elif command -v ftp >/dev/null 2>&1; then GET="ftp -o"
else echo "RESULT 取得の道具が無い"; exit 1; fi

T2="$W/t2"
echo "### 作業場 $W  prefix $PREFIX  段 $STAGE  取得 $GET"
uname -a
df -h "$W" 2>/dev/null | tail -1

say() { echo "RESULT $*"; }

echo '##### 1. pkgsrc を取る #####'
cd "$W" || exit 1
$GET pkgsrc.tar.gz "https://cdn.NetBSD.org/pub/pkgsrc/$BRANCH/pkgsrc.tar.gz" || { say "fetch pkgsrc: 落ちた"; exit 1; }
tar xzf pkgsrc.tar.gz || { say "extract pkgsrc: 落ちた"; exit 1; }
say "pkgsrc: 取れた"

echo '##### 2. bootstrap #####'
cd "$W/pkgsrc/bootstrap" || exit 1
# root でなければ --unprivileged が要る。macOS の runner は root ではなく、
# 無いと「You must be either root ... or use the --unprivileged option」で
# 止まる。root なら付けない (付けると pkgdb の場所が変わる)。
UNPRIV=
[ "$(id -u)" = "0" ] || UNPRIV=--unprivileged
./bootstrap --prefix "$PREFIX" --workdir "$W/bs" $UNPRIV >"$W/bootstrap.log" 2>&1
rc=$?
echo "  bootstrap の引数: --prefix $PREFIX $UNPRIV"
say "bootstrap: rc=$rc"
[ $rc -eq 0 ] || { tail -30 "$W/bootstrap.log"; exit 1; }
PATH=$PREFIX/bin:$PREFIX/sbin:$PATH; export PATH

# VM の cpu は 4 だが、pkgsrc は MAKE_JOBS を書かないと直列で建てる。mozc は
# 依存を含めて 6 時間近くかかり、GitHub の上限 (360 分) に当たった。
N=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)
cat >> "$PREFIX/etc/mk.conf" <<EOF
MAKE_JOBS=	$N
EOF
echo "  MAKE_JOBS=$N を mk.conf に書いた"

# bootstrap は digest を入れない。makepatchsum が呼ぶので先に建てる。
( cd "$W/pkgsrc/pkgtools/digest" && bmake install ) >"$W/digest.log" 2>&1 \
  || { say "digest: 落ちた"; tail -20 "$W/digest.log"; exit 1; }
say "digest: 入った"

echo '##### 3. package 一式を置く #####'
# 木の inputmethod/mozc-server を写して patches だけ差し替えるのでは足りない。
# gyp option は PR1 (pkg/60654) が足す options.mk と Makefile.common の変更で
# 入るもので、木にはまだ無い。NetBSD で建てて確かめた package 一式を持ってくる。
# 木の七本はどれも options.mk を読まない (PR1 が足すもので木に無い)。写しに
# 読ませるだけでなく、Makefile.common より前に置かなければ効かない。OSDEST は
# .if !empty(PKG_OPTIONS:Mgyp) の中で決まるので、PKG_OPTIONS が後から決まると
# 間に合わず、四つの BSD で OSDEST が空になって do-install が out_/Release を探す。
D="$W/pkgsrc/zakinko/mozc-server"
mkdir -p "$D"
cp "$WS/ci/mozc-bsd/pkg/"* "$D/" || { say "package: 落ちた"; exit 1; }
cp -R "$WS/ci/mozc-bsd/patches" "$D/patches" || { say "当て物: 落ちた"; exit 1; }
echo "  当て物 $(ls "$D/patches" | wc -l) 本"
cd "$D" || exit 1
bmake makepatchsum >"$W/mps.log" 2>&1 || { say "makepatchsum: 落ちた"; tail -10 "$W/mps.log"; }
say "当て物: 入れ替えた"

# util-linux の configure は AC_CHECK_TYPES([cpu_set_t]) で HAVE_CPU_SET_T を
# 決め、それで lib/cpuset.c を組む。DragonFly は cpu_set_t を持つので検査は
# 通るが、中身が glibc と違い __bits も __cpu_mask も無い。include/cpuset.h の
# 代替 macro がそれを使うので組めない。検査が型の名前しか見ていないのが元。
# mozc-server → devel/gyp → lang/python313 → devel/libuuid と繋がっていて、
# ここを抜けないと DragonFly で mozc を測れない。
if [ "$(uname -s)" = "DragonFly" ]; then
  L="$W/pkgsrc/zakinko/libuuid"
  cp -R "$W/pkgsrc/devel/libuuid" "$L"
  sed -i.bak 's|\.\./\.\./devel/libuuid/|../../zakinko/libuuid/|g' "$L/Makefile" 2>/dev/null
  # ac_cv_type_cpu_set_t=no で迂回する形から、上流へ出せる形に変えた。
  # 検査が型の名前しか見ていないのが元なので、code が使う欄も訊く当て物を
  # 生成済み configure に当てる。これが効くかを DragonFly で測る。
  cp "$WS/ci/mozc-bsd/libuuid/patch-configure-cpuset.diff" \
     "$L/patches/patch-configure-cpuset" 2>/dev/null
  ( cd "$L" && bmake makepatchsum ) >/dev/null 2>&1
  say "libuuid: cpu_set_t の欄を訊く当て物を入れた"
  rm -rf "$W/pkgsrc/devel/libuuid"
  ln -s "$L" "$W/pkgsrc/devel/libuuid"
  # 効いたかを直に見る
  ( cd "$L" && bmake configure ) >"$W/libuuid.log" 2>&1
  rc=$?
  say "libuuid configure: rc=$rc"
  grep -h 'cpu_set_t' "$W/libuuid.log" | head -4 | sed 's/^/    /'
fi

# NetBSD だけ gyp を選ばないので devel/bazel → lang/openjdk11 を建てにいき、
# CI ではそこで落ちる (cdefs_elf.h)。測りたいのは mozc なので、CI では四つの
# BSD を同じ経路に揃える。NetBSD を bazel で建てる側は techne で見ている。
if [ "$(uname -s)" = "NetBSD" ]; then
  echo "PKG_OPTIONS.mozc=	gyp" >> "$PREFIX/etc/mk.conf"
  say "NetBSD: CI では gyp に揃えた (bazel 経路は techne で測る)"
fi

echo '##### 4. option と platform の効き方 #####'
for v in OPSYS MACHINE_ARCH PKG_SUGGESTED_OPTIONS PKG_OPTIONS PKG_FAIL_REASON USE_X11 PATCHDIR; do
  printf '  %-22s %s\n' "$v" "$(bmake show-var VARNAME=$v 2>/dev/null | cut -c1-90)"
done

echo '##### 4b. gyp が名乗る flavor #####'
# gyp の GetFlavor は sys.platform を見て freebsd/openbsd/netbsd を返し、
# 知らない物は全部 'linux' に落とす。dragonfly の枝は無い。common.gypi に
# OS=="dragonfly" と書いても永遠に成立しないので、先に測る。
for py in python3 python3.13 python3.12 python3.11 python; do
  command -v $py >/dev/null 2>&1 || continue
  echo "  sys.platform = $($py -c 'import sys; print(sys.platform)')"
  $py - <<'EOF'
import sys
f = {'cygwin':'win','win32':'win','darwin':'mac'}
p = sys.platform
if p in f: v = f[p]
elif p.startswith('sunos'): v = 'solaris'
elif p.startswith('freebsd'): v = 'freebsd'
elif p.startswith('openbsd'): v = 'openbsd'
elif p.startswith('netbsd'): v = 'netbsd'
elif p.startswith(('aix','zos','os390')): v = 'aix/zos'
else: v = 'linux'
print("  gyp の flavor = " + v)
EOF
  break
done

echo '##### 4c. pkg-config が動くか #####'
# OpenBSD で pkgconf-3.0.7 が Segmentation fault (core dumped) を出し、
# libxml2 の configure が「pkg-config not found」で止まる。
#   mozc-server → ninja-build → re2c → cmake → curl → nghttp2 → libxml2
# 4 時間待たずに見えるよう、probe の段で撃っておく。
# 落ちるのは pkgsrc が入れる pkgconf であって、base の物ではない。bootstrap の
# 直後には base の物しか PATH に無いので、先に devel/pkgconf を入れてから撃つ。
# 一度これで base の /usr/bin/pkg-config (2.4.3、正常) を測って取り違えた。
( cd "$W/pkgsrc/devel/pkgconf" && bmake install ) >"$W/pkgconf.log" 2>&1 \
  && say "devel/pkgconf: 入った" || { say "devel/pkgconf: 落ちた"; tail -20 "$W/pkgconf.log"; }
for B in "$PREFIX/bin/pkg-config" "$PREFIX/bin/pkgconf" /usr/bin/pkg-config; do
  [ -x "$B" ] || continue
  printf '  %s\n' "$B"
  "$B" --version >"$W/pc.out" 2>&1
  rc=$?
  if [ $rc -gt 128 ]; then
    printf '    ★ signal %d で落ちた (core)\n' "$((rc - 128))"
  else
    printf '    --version rc=%d  %s\n' "$rc" "$(head -1 "$W/pc.out")"
  fi
  # configure が実際に使う形も撃つ
  "$B" --atleast-pkgconfig-version 0.9.0 >/dev/null 2>&1
  printf '    --atleast-pkgconfig-version 0.9.0 rc=%d\n' "$?"
done
printf '  PATH で先に見つかるのは: %s\n' "$(command -v pkg-config 2>/dev/null)"

# 直接呼ぶ限り pkgconf は落ちない (--version も --atleast も rc=0)。build の
# 中で落ちるので、環境が条件。pkgsrc は cwrapper 経由で呼び PKG_CONFIG_LIBDIR
# を張る。libxml2 の configure が実際に落ちる所なので、そこだけ再現する。
# mozc 全体の 4 時間を待たずに 20 分で分かる。
# util-linux の configure が cpu_set_t の型名しか見ていない件の根拠。
# 別の run を起こさず、ここで一緒に測る (account 全体で runner が詰まっている)。
echo '##### 4c2. util-linux が見ている cpu_set_t ==='
cat > "$T2.c" <<'EOF'
#include <sched.h>
#include <stdio.h>
int main(void){
#ifdef __linux__
#endif
  return 0;
}
EOF
for t in 'cpu_set_t s; (void)s;|型が在る' \
         '(void)CPU_ALLOC(1);|CPU_ALLOC が宣言されている' \
         'cpu_set_t s; (void)s.__bits;|cpu_set_t に __bits' \
         '__cpu_mask m = 0; (void)m;|__cpu_mask が在る'; do
  body=${t%%|*}; name=${t##*|}
  printf '#include <sched.h>\nint main(void){ %s return 0; }\n' "$body" > "$T2.c"
  printf '  %-34s ' "$name"
  ${CC:-cc} -o "$T2" "$T2.c" >/dev/null 2>&1 && echo '通る' || echo '通らない'
done

echo '##### 4d. libxml2 の configure を再現する #####'
( cd "$W/pkgsrc/textproc/libxml2" && bmake configure ) >"$W/libxml2.log" 2>&1
rc=$?
say "libxml2 configure: rc=$rc"
if [ $rc -ne 0 ]; then
  grep -n -B6 -A2 -iE 'segmentation|core dumped|pkg-config not found|error:' "$W/libxml2.log" | tail -40
  echo "--- configure が使った pkg-config ---"
  grep -n 'PKG_CONFIG' "$W/libxml2.log" | head -5
  W2=$(ls -d "$W/pkgsrc/textproc/libxml2/work/.tools/bin" 2>/dev/null)
  if [ -n "$W2" ]; then
    echo "--- cwrapper を直に撃つ (素の環境) ---"
    "$W2/pkg-config" --atleast-pkgconfig-version 0.9.0; printf '    rc=%d\n' "$?"
    # 直に撃つと落ちない。configure の中でだけ落ちるので、configure が張る
    # 環境を一つずつ足して、どれが効くかを見る。
    echo "--- configure が張る環境を足して撃つ ---"
    B="$W/pkgsrc/textproc/libxml2/work"
    for v in "PKG_CONFIG_LIBDIR=$B/.buildlink/lib/pkgconfig:$B/.buildlink/share/pkgconfig" \
             "PKG_CONFIG_PATH=" \
             "PKG_CONFIG_LOG=$B/../.pkg-config.log"; do
      printf '    %-46s ' "$(echo "$v" | cut -c1-44)"
      env "$v" "$W2/pkg-config" --atleast-pkgconfig-version 0.9.0 >/dev/null 2>&1
      r=$?
      [ $r -gt 128 ] && printf 'signal %d (core)\n' "$((r-128))" || printf 'rc=%d\n' "$r"
    done
    echo "--- 三つまとめて ---"
    env "PKG_CONFIG_LIBDIR=$B/.buildlink/lib/pkgconfig:$B/.buildlink/share/pkgconfig" \
        "PKG_CONFIG_PATH=" "PKG_CONFIG_LOG=$B/../.pkg-config.log" \
        "$W2/pkg-config" --atleast-pkgconfig-version 0.9.0 >/dev/null 2>&1
    r=$?
    [ $r -gt 128 ] && printf '    signal %d (core)\n' "$((r-128))" || printf '    rc=%d\n' "$r"
    echo "--- core は出来ているか ---"
    ls -l "$B"/../*.core "$B"/*.core 2>/dev/null | head -3
  fi
fi

echo '##### 5. 依存が解けるか #####'
bmake show-depends-dirs >"$W/depends.log" 2>&1
say "depends: rc=$? ($(grep -c . "$W/depends.log") 行)"
head -20 "$W/depends.log"

echo '##### 6. 配布物が取れるか #####'
bmake fetch >"$W/fetch.log" 2>&1
say "fetch: rc=$?"
tail -8 "$W/fetch.log"

[ "$STAGE" = "probe" ] && { echo "### probe まで。ここで止める"; exit 0; }

echo '##### 7. 建てる #####'
bmake package >"$W/build.log" 2>&1
rc=$?
say "package: rc=$rc"
if [ $rc -ne 0 ]; then
  # artifact は VM の workspace から runner へ戻らなかったので、job の log へ
  # 直に吐く。原因は「stopped making in <pkg>」の何十行も上に在る。
  echo "--- error を含む行とその前後 ---"
  grep -n -B4 -A2 -iE 'error:|fatal error|undefined (reference|symbol)' "$W/build.log" \
    | tail -120
  echo "--- build.log の末尾 200 行 ---"
  tail -200 "$W/build.log"
  exit 1
fi
ls -l "$W/pkgsrc/packages/All/"mozc-server-*.tgz 2>/dev/null
