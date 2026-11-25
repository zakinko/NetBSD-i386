#!/bin/sh
# augeas の PR の枝 (tarball) を測る。.github/workflows/augeas-pr.yml から。
#	BSDMAKE=make GMAKE=gmake sh augeas-pr.sh <tarball の dir>
set -u
D=$1
W=${TMPDIR:-/var/tmp}/augpr.$$
mkdir -p "$W"
OS=$(uname -s)
say() { echo "RESULT $OS $*"; }
say "sh: $(ls -l /bin/sh | sed 's/.* \/bin/\/bin/')  bash: $(command -v bash || echo 無し)"
for b in test-master test-889 test-895; do
	mkdir -p "$W/$b" && (cd "$W/$b" && gzip -dc "$D/$b.tar.gz" | tar xf - && mv augeas-* src)
done

# #895: 三つの試験。master は対照
for b in test-master test-895; do
	cd "$W/$b/src"
	./configure >"$W/$b.conf" 2>&1 || { say "$b configure NG"; tail -15 "$W/$b.conf"; continue; }
	$GMAKE >"$W/$b.make" 2>&1 || { say "$b make NG"; tail -15 "$W/$b.make"; continue; }
	for t in test-augprint test-augtool test-createfile; do
		(cd tests && $GMAKE check TESTS="$t.sh" >"$W/$b.$t" 2>&1)
		r=$(grep -E '^(PASS|FAIL|ERROR|SKIP): ' "$W/$b.$t" | head -1)
		say "$b $t: ${r:-結果なし}"
		case $r in PASS*) ;; *) tail -25 "tests/$t.log" 2>/dev/null ;; esac
	done
	[ $b = test-895 ] && (cd tests && $GMAKE check >"$W/all" 2>&1; grep -E '^# (TOTAL|PASS|FAIL|ERROR|SKIP):' "$W/all" | tr '\n' ' ' | sed "s/^/RESULT $OS test-895 全部 /"; echo; grep -E '^FAIL' "$W/all" | head -10)
	[ $b = test-master ] && (cd tests && $GMAKE check >"$W/all" 2>&1; grep -E '^# (TOTAL|PASS|FAIL|ERROR|SKIP):' "$W/all" | tr '\n' ' ' | sed "s/^/RESULT $OS test-master 全部 /"; echo; grep -E '^FAIL' "$W/all" | head -10)
done
# 箱にある他の sh でも三つを走らせる
cd "$W/test-895/src/tests"
for s in dash "busybox sh" ksh mksh; do
	command -v ${s%% *} >/dev/null 2>&1 || continue
	for t in test-augprint test-augtool test-createfile; do
		(cd "$W/test-895/src/tests"; abs_top_builddir=$W/test-895/src abs_top_srcdir=$W/test-895/src abs_builddir=$PWD abs_srcdir=$PWD srcdir=. \
			PATH=$W/test-895/src/src:$PATH $s ./$t.sh >"$W/o" 2>&1) && say "test-895 $t ($s): 通る" || { say "test-895 $t ($s): 落ちる"; tail -8 "$W/o"; }
	done
done

# #889: lens の install を、木の中と外、GNU make と BSD make で
for b in test-master test-889; do
	for mk in "$GMAKE" "$BSDMAKE"; do
		for where in in out; do
			B=$W/$b.$where.$(basename $mk); rm -rf "$B"
			if [ $where = in ]; then cp -R "$W/$b/src" "$B"; c=./configure; else mkdir "$B"; c=$W/$b/src/configure; fi
			# 外で組むには、木の中が configure 済みであってはならない
			if [ $where = out ] && [ -f "$W/$b/src/Makefile" ]; then (cd "$W/$b/src" && $GMAKE distclean >/dev/null 2>&1); fi
			(cd "$B" && $c >"$W/c" 2>&1) || { say "$b $mk $where configure NG"; tail -5 "$W/c"; continue; }
			(cd "$B" && $mk DESTDIR="$B/dest" install-dist_lensDATA install-dist_lenstestDATA >"$W/i" 2>&1); rc=$?
			n=$(find "$B/dest" -name '*.aug' 2>/dev/null | wc -l | tr -d ' ')
			say "$b $mk $where: lens の install $n 個 rc=$rc"
			[ $rc = 0 ] || tail -4 "$W/i"
		done
	done
	# dist の中身。BSD make と GNU make で同じか
	for mk in "$GMAKE" "$BSDMAKE"; do
		B=$W/$b.in.$(basename $mk)
		(cd "$B" && rm -rf dest && $mk distdir >"$W/dd" 2>&1); rc=$?
		(cd "$B" && find augeas-*/ -type f 2>/dev/null | sed 's,^[^/]*/*,,' | sort) >"$W/l.$(basename $mk)"
		say "$b $mk distdir rc=$rc files=$(wc -l <"$W/l.$(basename $mk)" | tr -d ' ')"
		[ $rc = 0 ] || tail -4 "$W/dd"
	done
	cmp -s "$W/l.$(basename $GMAKE)" "$W/l.$(basename $BSDMAKE)" && say "$b distdir: 二つの make で同じ" || { say "$b distdir: 違う"; diff "$W/l.$(basename $GMAKE)" "$W/l.$(basename $BSDMAKE)" | head -8; }
done
# 全体が BSD make で建つか
B=$W/full; cp -R "$W/test-889/src" "$B"
(cd "$B" && { [ -f Makefile ] || ./configure >/dev/null 2>&1; } && $BSDMAKE >"$W/f" 2>&1 && $BSDMAKE DESTDIR="$B/dest" install >>"$W/f" 2>&1); say "test-889 $BSDMAKE 全体の build と install rc=$? lens=$(find "$B/dest" -name '*.aug' 2>/dev/null | wc -l | tr -d ' ')"
tail -4 "$W/f"
exit 0
