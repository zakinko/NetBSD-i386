#!/bin/sh
# How far does a MinGW build of XEmacs 21.5 get?  A probe, not a test:
# it never fails the job, it counts the walls.
#
#	$1	mingw32 | mingw64   (the MSYS2 environment the job set up)
#	$2	the checkout (from fetch-upstream.sh)
#	$3	directory for the logs
#
# configure.ac recognises MinGW only as *-pc-mingw*, and only under
# i[3-9]86-*-*.  MSYS2 hands configure the build type i686-w64-mingw32 or
# x86_64-w64-mingw32: vendor w64, not pc.  Both are configured as generic
# Unix, WIN32_NATIVE is never defined, and the build stops on sys/errno.h.
# The probe edits the shipped configure so both branches take *-mingw*;
# it edits configure rather than configure.ac to see the next wall
# without regenerating it, and is not a proposed change.

set -u
MODE=$1 SRC=$2 OUT=$3
mkdir -p "$OUT"
cd "$SRC" || exit 0
echo "== $MODE: upstream $(cat .upstream-rev), $(uname -s), $(gcc -dumpmachine) =="

awk '{ sub(/^      \*-pc-mingw\* \)/, "      *-mingw* )"); print }
     /^      \*-cygwin\* \)\topsys=cygwin64 ;;$/ {
       print "      *-mingw* )\topsys=mingw32 ;"
       print "\t\t\t\ttest -z \"$with_tty\" && with_tty=\"no\";;"
     }' configure > configure.new && mv configure.new configure && chmod +x configure
echo "configure matches *-mingw* in $(grep -c -- '\*-mingw\* )' configure) places (expect 2)"

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
