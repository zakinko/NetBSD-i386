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

# configure writes #include "$srcdir/src/s/mingw32.h" into its test
# programs, with srcdir from `cd $srcdir && pwd`, which MSYS answers in
# /d/a/... form; MSYS2 converts paths on command lines but not inside
# files, so the native gcc cannot open it and the switches in
# s/mingw32.h are never picked up.  Use pwd -W, the D:/... form, in those
# two lines only; elsewhere the path reaches gcc on its command line.
perl -pi -e 's{^#include "\$srcdir/src/\$(opsysfile|machfile)"$}{#include "\$(cd "\$srcdir" && (pwd -W 2>/dev/null || pwd))/src/\$$1"}' configure
echo "configure writes a native path in $(grep -c 'pwd -W' configure) include lines (expect 2)"

# s/mingw32.h is from the days of Cygwin's gcc -mno-cygwin.
patch -p1 -f -i "$GITHUB_WORKSPACE/ci/xemacs/mingw-wip.patch" </dev/null
grep -q '^#include <../include/process.h>' src/s/mingw32.h src/sysproc.h

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

# The build runs the xemacs it has just linked (update-elc, the dump).
# The 32-bit run of the seventh probe sat for over half an hour with no
# way to see where; bound it, and show where it was when it stopped.
timeout 1500 make -k -j"$(nproc)" > "$OUT/make.log" 2>&1
rc=$?
echo "make -k exited $rc"
if [ $rc -eq 124 ]; then
  echo "!! make did not finish in 25 minutes; the last lines:"
  tail -15 "$OUT/make.log"
fi
[ -f src/xemacs.exe ] && echo "src/xemacs.exe built" || echo "no src/xemacs.exe"

# The eighth probe stopped here: the first run of the new xemacs in the
# build (update-elc, with -nd) sat until the 30-minute bound, on 32-bit
# and 64-bit alike.  It is a -mwindows program with no console; a fatal
# error in such a program can be a message box that waits for a click.
# Run that one step on its own and look at the screen while it waits.
if [ -f src/xemacs.exe ] && [ ! -f src/xemacs.dmp ]; then
  PS=/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  ( cd src && timeout 90 ./xemacs -nd -no-packages -no-configured-paths \
      -batch -l ../lisp/update-elc.el > "$OUT/update-elc.out" 2>&1; \
    echo "update-elc exited $?" >> "$OUT/update-elc.out" ) &
  sleep 20
  "$PS" -NoProfile -ExecutionPolicy Bypass \
    -File "$(cygpath -w "$GITHUB_WORKSPACE/ci/xemacs/screenshot.ps1")" \
    "$(cygpath -w "$OUT/update-elc-hang.png")"
  wait
  echo "--- update-elc on its own ---"
  cat "$OUT/update-elc.out"
fi

# An executable is not a working XEmacs: the dump may not have happened.
# It is linked -mwindows and prints nothing to the console, so ask it to
# write what it knows to a file.
if [ -f src/xemacs.exe ]; then
  ls -l src/xemacs.exe src/*.dmp 2>&1 | sed 's/^/  /'
  MINGW_LOG=$(cygpath -m "$OUT/run.log"); export MINGW_LOG
  rm -f "$OUT/run.log"
  timeout 120 src/xemacs.exe -batch -vanilla \
    -l "$(cygpath -m "$GITHUB_WORKSPACE/ci/xemacs/mingw-run.el")"
  echo "xemacs.exe exited $?"
  echo "--- what it wrote ---"
  cat "$OUT/run.log" 2>/dev/null || echo "(nothing written)"
fi

echo "--- files with compile errors: first error in each ---"
# Key each error by its file.  The paths can be absolute with a drive
# letter (D:/a/.../minitar.c:115:17:), so the file is everything before
# the last :LINE:COL:, not everything before the first colon; the first
# version split on the first colon and reported 0 files while three were
# failing.
grep -E '\.(c|h):[0-9]+:[0-9]+: (fatal )?error:' "$OUT/make.log" \
  | awk '{ f = $0; sub(/:[0-9]+:[0-9]+: .*/, "", f); if (!seen[f]++) print }' \
  | tee "$OUT/walls.txt" | head -60
echo "--- totals ---"
echo "files with errors: $(wc -l < "$OUT/walls.txt")"
echo "error lines: $(grep -cE '(fatal )?error:' "$OUT/make.log")"
echo "missing headers: $(grep -oE "fatal error: [^:]+: No such file" "$OUT/make.log" | sort -u | tr '\n' ' ')"
echo "unrecognized options: $(grep -oE "unrecognized command-line option '[^']+'" "$OUT/make.log" | sort -u | tr '\n' ' ')"
exit 0
