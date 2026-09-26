#!/bin/sh
# Build XEmacs 21.5 with configure, with or without the Windows module
# patch, try the sample module through ellcc, and run make check.  For
# the configure-based builds the patch also reaches: Cygwin and MinGW
# (MSYS2), where src/Makefile.in.in makes the export table with dlltool.
#
#	$1	a checkout (from fetch-upstream.sh)
#	$2	base | patched
#	$3	directory for the results: module.log, module.result, check.log
#
# CONF_ARGS, if set, replaces the configure options.
#
# The module step's outcome is recorded, not fatal: if the base tree
# cannot build or load a module on this platform either, that is not
# the patch's doing, and make check still has to be compared.

set -eu
SRC=$1 TREE=$2 OUT=$3
mkdir -p "$OUT"
cd "$SRC"
case "$TREE" in
  base)    ;;
  patched) patch -p1 -f -i "$GITHUB_WORKSPACE/ci/xemacs/win-module-exports.patch" </dev/null
	   grep -q 'emodule_noop_' lisp/ellcc.el ;;
  *) echo "base or patched" >&2; exit 2 ;;
esac
echo "== $TREE: upstream $(cat .upstream-rev), $(uname -s) =="

: "${CONF_ARGS:=--with-modules --without-x --with-postgresql=no --with-ldap=no --with-sound=none}"
# shellcheck disable=SC2086
./configure $CONF_ARGS > conf.log 2>&1 || { echo "!! configure"; tail -40 conf.log; exit 4; }
grep -E 'Compiling in support for dynamic shared object modules|modules' conf.log | head -5 || true
make -j"$(nproc)" > make.log 2>&1 || { echo "!! make"; tail -60 make.log; exit 5; }
X="$SRC/src/xemacs"
[ -x "$X" ] || [ -x "$X.exe" ] || { echo "!! no src/xemacs"; exit 6; }
"$X" -batch -vanilla -eval '(princ (format "%s %s modules=%s\n" emacs-version system-configuration (featurep (quote modules))))'

M="$SRC/modules/sample/external"
E="$SRC/lisp/ellcc.el"
module() {
  ellcc() { ( cd "$M" && "$X" -batch --script "$E" -- --mode=verbose "$@" ); }
  ellcc --mode=init --mod-output=sample_i.c --mod-name=sample \
	--mod-version=0.0.1 --mod-title=Sample sample.c
  ellcc --mode=compile -I"$SRC/src" -c sample.c
  ellcc --mode=compile -I"$SRC/src" -c sample_i.c
  ellcc --mode=link --mod-output=sample.ell sample.o sample_i.o
  ls -l "$M/sample.ell"
  nm -g "$M/sample.ell" 2>/dev/null | grep -E 'emodule_|_of_sample|unload_sample' || true
  out=$(SAMPLE_ELL="$M/sample.ell" "$X" -batch -vanilla \
	  -l "$GITHUB_WORKSPACE/ci/xemacs/module-load.el" 2>&1) || true
  echo "$out"
  for pat in 'loaded=t' 'sample-function=t' 'list-modules=.*sample'; do
    echo "$out" | grep -Eq "$pat" || { echo "not seen: $pat"; return 1; }
  done
}
if ( module ) > "$OUT/module.log" 2>&1; then
  echo loaded > "$OUT/module.result"
else
  echo failed > "$OUT/module.result"
fi
echo "--- module: $(cat "$OUT/module.result") ---"
tail -40 "$OUT/module.log"

make check > "$OUT/check.log" 2>&1 || echo "make check exited $?"
grep -E 'tests successful|No tests run|\(aborted\)' "$OUT/check.log" | tr -d '\r' | tail -45 || true
