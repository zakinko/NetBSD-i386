#!/bin/sh
# How far does a MinGW build of XEmacs 21.5 get?  A probe, not a test:
# it never fails the job, it counts the walls.
#
#	$1	mingw32        MSYS2 MINGW32 (i686), configure as shipped
#		mingw64-match  MSYS2 MINGW64, with the x86_64 branch of the
#		               generated configure taught to recognise MinGW,
#		               as the i386 branch already does
#	$2	the checkout (from fetch-upstream.sh)
#	$3	directory for the logs
#
# configure.ac matches MinGW only under i[3-9]86-*-* (as *-pc-mingw*),
# and config.guess calls MSYS2's MINGW64 x86_64-pc-mingw64, so a 64-bit
# build is configured as generic Unix.  mingw64-match edits the shipped
# configure rather than configure.ac, to see the next wall without
# regenerating it; it is not a proposed change.

set -u
MODE=$1 SRC=$2 OUT=$3
mkdir -p "$OUT"
cd "$SRC" || exit 0
echo "== $MODE: upstream $(cat .upstream-rev), $(uname -s), $(gcc -dumpmachine) =="

if [ "$MODE" = mingw64-match ]; then
  awk '{ print }
       /^      \*-cygwin\* \)\topsys=cygwin64 ;;$/ {
         print "      *-pc-mingw* )\topsys=mingw32 ;"
         print "\t\t\t\ttest -z \"$with_tty\" && with_tty=\"no\";;"
       }' configure > configure.new && mv configure.new configure && chmod +x configure
  echo "configure now matches MinGW in $(grep -c 'opsys=mingw32' configure) places"
fi

# configure writes #include "$srcdir/src/m/intel386.h" into its test
# programs.  With srcdir in MSYS form (/d/a/...), the native MinGW gcc
# cannot open it: the first probe stopped there, the switches in
# s/mingw32.h (-DWIN32_NATIVE among them) were never picked up, and the
# build went on as generic Unix.  MSYS2 converts paths on command lines,
# not inside files, so give srcdir in the D:/... form both can read.
SRCDIR=$(cygpath -m "$PWD")
echo "srcdir: $SRCDIR"
./configure --srcdir="$SRCDIR" --with-modules --without-x \
  --with-postgresql=no --with-ldap=no --with-sound=none > "$OUT/conf.log" 2>&1
echo "configure exited $?"
grep -m3 -E "^opsys=|^machine=|^canonical=" config.log || true
grep -m8 -iE 'unrecognized|error:|No such file' "$OUT/conf.log" config.log || true
grep -E "^c_switch_system=|^opsysfile=|^machfile=" config.log || true

make -k -j"$(nproc)" > "$OUT/make.log" 2>&1
echo "make -k exited $?"
[ -f src/xemacs.exe ] && echo "src/xemacs.exe built" || echo "no src/xemacs.exe"

echo "--- files with compile errors: first error in each ---"
grep -E '^[^ :]+\.(c|h):[0-9]+:[0-9]+: (fatal )?error:' "$OUT/make.log" \
  | awk -F: '!seen[$1]++ { print }' | tee "$OUT/walls.txt" | head -60
echo "--- totals ---"
echo "files with errors: $(wc -l < "$OUT/walls.txt")"
echo "error lines: $(grep -cE '(fatal )?error:' "$OUT/make.log")"
echo "missing headers: $(grep -oE "fatal error: [^:]+: No such file" "$OUT/make.log" | sort -u | tr '\n' ' ')"
echo "unrecognized options: $(grep -oE "unrecognized command-line option '[^']+'" "$OUT/make.log" | sort -u | tr '\n' ' ')"
exit 0
