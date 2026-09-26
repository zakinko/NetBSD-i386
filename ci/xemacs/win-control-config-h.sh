#!/bin/sh
# Control for the src/config.h.in part of win-module-exports.patch:
# apply the whole patch, then take back only the config.h.in hunks.
# The build should then fail at the xemacs.exe link with LNK2001 on the
# inline functions xemacs.def names, which is what that hunk is for.
#
#	$1	the checkout (not yet patched)

set -eu
cd "$1"
P="$GITHUB_WORKSPACE/ci/xemacs/win-module-exports.patch"
patch -p1 -f -i "$P" </dev/null
awk '/^--- a\//{keep = ($0 == "--- a/src/config.h.in")} keep' "$P" > config-h.patch
grep -q '^+#if !defined (USE_GPLUSPLUS) && !defined (USE_CPLUSPLUS)' config-h.patch
patch -p1 -R -f -i config-h.patch </dev/null
if grep -q 'USE_CPLUSPLUS' src/config.h.in; then
  echo "config.h.in still has the change" >&2; exit 3
fi
echo "config.h.in reverted; the rest of the patch stays"
