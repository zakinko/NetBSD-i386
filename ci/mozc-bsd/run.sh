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

# bootstrap は digest を入れない。makepatchsum が呼ぶので先に建てる。
( cd "$W/pkgsrc/pkgtools/digest" && bmake install ) >"$W/digest.log" 2>&1 \
  || { say "digest: 落ちた"; tail -20 "$W/digest.log"; exit 1; }
say "digest: 入った"

echo '##### 3. package 一式を置く #####'
# 木の inputmethod/mozc-server を写して patches だけ差し替えるのでは足りない。
# gyp option は PR1 (pkg/60654) が足す options.mk と Makefile.common の変更で
# 入るもので、木にはまだ無い。NetBSD で建てて確かめた package 一式を持ってくる。
D="$W/pkgsrc/zakinko/mozc-server"
mkdir -p "$D"
cp "$WS/ci/mozc-bsd/pkg/"* "$D/" || { say "package: 落ちた"; exit 1; }
cp -R "$WS/ci/mozc-bsd/patches" "$D/patches" || { say "当て物: 落ちた"; exit 1; }
echo "  当て物 $(ls "$D/patches" | wc -l) 本"
cd "$D" || exit 1
bmake makepatchsum >"$W/mps.log" 2>&1 || { say "makepatchsum: 落ちた"; tail -10 "$W/mps.log"; }
say "当て物: 入れ替えた"

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
  grep -iE 'error:|Error code|fatal' "$W/build.log" | head -20
  tail -30 "$W/build.log"
  exit 1
fi
ls -l "$W/pkgsrc/packages/All/"mozc-server-*.tgz 2>/dev/null
