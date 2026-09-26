#!/bin/sh
# Build XEmacs 21.5 on Linux and run `make check', with or without the
# Windows module patch.  The two trees are built with the same options
# so check-compare.py can set one log against the other.
#
#	$1	a checkout of zakinko/XEmacs
#	$2	base | patched
#	$3	where to write the make check log

set -eu
SRC=$1 TREE=$2 LOG=$3
cd "$SRC"
case "$TREE" in
  base)    ;;
  patched) patch -p1 -f -i "$GITHUB_WORKSPACE/ci/xemacs/win-module-exports.patch" </dev/null
	   grep -q 'emodule_noop_' lisp/ellcc.el ;;
  *) echo "base or patched" >&2; exit 2 ;;
esac
echo "== $TREE: $(git log --oneline -1) =="
git status --short

# The same options as linux-module-sample.sh.
./configure --with-modules --without-x \
    --with-msw=no --with-postgresql=no --with-ldap=no --with-sound=none \
    > conf.log 2>&1 || { echo "!! configure"; tail -30 conf.log; exit 4; }
make -j"$(nproc)" > make.log 2>&1 || { echo "!! make"; tail -40 make.log; exit 5; }

# make check exits non-zero when any test fails, and the base tree has
# failures of its own; the comparison is what decides.
make check > "$LOG" 2>&1 || echo "make check exited $?"
grep -E 'tests successful|No tests run|\(aborted\)' "$LOG" | tail -60
