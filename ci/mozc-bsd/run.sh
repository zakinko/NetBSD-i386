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
for d in /home /usr/home /var/tmp /tmp; do
  [ -d "$d" ] && W="$d/mozcwork" && break
done
PREFIX=/usr/pkg
mkdir -p "$W" || exit 1
echo "### 作業場 $W  prefix $PREFIX  段 $STAGE"
df -h "$W" | tail -1

say() { echo "RESULT $*"; }

echo '##### 1. pkgsrc を取る #####'
cd "$W" || exit 1
if command -v fetch >/dev/null 2>&1; then GET="fetch -o"; else GET="ftp -o"; fi
$GET pkgsrc.tar.gz "https://cdn.NetBSD.org/pub/pkgsrc/$BRANCH/pkgsrc.tar.gz" || { say "fetch pkgsrc: 落ちた"; exit 1; }
tar xzf pkgsrc.tar.gz || { say "extract pkgsrc: 落ちた"; exit 1; }
say "pkgsrc: 取れた"

echo '##### 2. bootstrap #####'
cd "$W/pkgsrc/bootstrap" || exit 1
./bootstrap --prefix "$PREFIX" --workdir "$W/bs" >"$W/bootstrap.log" 2>&1
rc=$?
say "bootstrap: rc=$rc"
[ $rc -eq 0 ] || { tail -30 "$W/bootstrap.log"; exit 1; }
PATH=$PREFIX/bin:$PREFIX/sbin:$PATH; export PATH

# bootstrap は digest を入れない。makepatchsum が呼ぶので先に建てる。
( cd "$W/pkgsrc/pkgtools/digest" && bmake install ) >"$W/digest.log" 2>&1 \
  || { say "digest: 落ちた"; tail -20 "$W/digest.log"; exit 1; }
say "digest: 入った"

echo '##### 3. mozc-server を写して当て物を入れ替える #####'
D="$W/pkgsrc/zakinko/mozc-server"
mkdir -p "$W/pkgsrc/zakinko"
cp -R "$W/pkgsrc/inputmethod/mozc-server" "$D" || { say "写し: 落ちた"; exit 1; }
rm -rf "$D/patches"
cp -R "$WS/ci/mozc-bsd/patches" "$D/patches" || { say "当て物: 落ちた"; exit 1; }
# 写しが自分を指すように直す。Makefile だけでなく Makefile.common も。
sed -i.bak 's|\.\./\.\./inputmethod/mozc-server/|../../zakinko/mozc-server/|g' \
  "$D/Makefile" "$D/Makefile.common" 2>/dev/null
echo "  当て物 $(ls "$D/patches" | wc -l) 本"
cd "$D" || exit 1
bmake makepatchsum >"$W/mps.log" 2>&1 || { say "makepatchsum: 落ちた"; tail -10 "$W/mps.log"; }
say "当て物: 入れ替えた"

echo '##### 4. option と platform の効き方 #####'
for v in OPSYS MACHINE_ARCH PKG_SUGGESTED_OPTIONS PKG_OPTIONS PKG_FAIL_REASON USE_X11 PATCHDIR; do
  printf '  %-22s %s\n' "$v" "$(bmake show-var VARNAME=$v 2>/dev/null | cut -c1-90)"
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
