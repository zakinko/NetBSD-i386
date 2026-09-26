#!/bin/sh
# Fetch XEmacs 21.5 from upstream Heptapod at the changeset the workflow
# pins in XEMACS_UPSTREAM, and unpack it as DEST.
#
# The jobs used to clone the GitHub mirror, which had stopped at
# 2026-09-07; upstream had since released 21.5.37 and changed
# src/xemacs.def.in.in.  What is sent must be what was measured, so take
# the tree from upstream itself, by its hash.
#
#	$1	directory to create

set -eu
DEST=$1
REV=${XEMACS_UPSTREAM:?XEMACS_UPSTREAM is not set}
[ ! -e "$DEST" ] || { echo "$DEST already exists" >&2; exit 2; }
T=$(mktemp -d)
curl -fsSL --retry 3 -o "$T/x.tgz" \
  "https://foss.heptapod.net/xemacs/xemacs/-/archive/$REV/xemacs-$REV.tar.gz"
tar xzf "$T/x.tgz" -C "$T"
set -- "$T"/xemacs-*/
[ $# -eq 1 ] && [ -d "$1" ] || { echo "unexpected archive layout" >&2; ls "$T" >&2; exit 3; }
mv "$1" "$DEST"
rm -rf "$T"
echo "$REV" > "$DEST/.upstream-rev"
echo "upstream $REV -> $DEST"
