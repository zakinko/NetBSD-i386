#!/bin/sh
# XEmacs 21.5 on Linux with the Windows module patch applied: the patch
# touches lisp/ellcc.el, which every platform uses, and src/config.h.in.
# Build the tree, then build modules/sample/external with the in-tree
# ellcc.el and load it, the same steps the Windows job takes.
#
#	$1	a checkout of zakinko/XEmacs

set -eu
SRC=$1
P="$GITHUB_WORKSPACE/ci/xemacs/win-module-exports.patch"
cd "$SRC"

patch -p1 -f -i "$P" </dev/null
grep -q 'emodule_noop_' lisp/ellcc.el
grep -q 'USE_CPLUSPLUS' src/config.h.in

# 21.5's configure rejects options it does not know, and several of
# 21.4's are gone: MULE is always on, the portable dumper is the
# default, and X is autoconf's own --without-x.
./configure --with-modules --without-x \
    --with-msw=no --with-postgresql=no --with-ldap=no --with-sound=none \
    > conf.log 2>&1 || { echo "!! configure"; tail -30 conf.log; exit 4; }
grep -i 'modules' conf.log | head -5 || true
make -j"$(nproc)" > make.log 2>&1 || { echo "!! make"; tail -40 make.log; exit 5; }
X="$SRC/src/xemacs"
[ -x "$X" ] || { echo "!! no src/xemacs"; exit 6; }
"$X" -batch -vanilla -eval '(princ (format "%s modules=%s\n" emacs-version (featurep (quote modules))))'

M="$SRC/modules/sample/external"
E="$SRC/lisp/ellcc.el"
ellcc() { ( cd "$M" && "$X" -batch --script "$E" -- --mode=verbose "$@" ); }

ellcc --mode=init --mod-output=sample_i.c --mod-name=sample \
      --mod-version=0.0.1 --mod-title=Sample sample.c
echo "--- sample_i.c ---"; cat "$M/sample_i.c"
ellcc --mode=compile -c sample.c
ellcc --mode=compile -c sample_i.c
ellcc --mode=link --mod-output=sample.ell sample.o sample_i.o
ls -l "$M/sample.ell"
nm -D --defined-only "$M/sample.ell" | grep -E 'emodule_|_of_sample|unload_sample'

out=$(SAMPLE_ELL="$M/sample.ell" "$X" -batch -vanilla \
        -l "$GITHUB_WORKSPACE/ci/xemacs/module-load.el")
echo "$out"
for pat in 'loaded=t' 'sample-function=t' 'sample-boolean=nil' 'list-modules=.*sample'; do
  echo "$out" | grep -Eq "$pat" || { echo "!! not seen: $pat"; exit 7; }
done
echo "sample module built by ellcc and loaded"
