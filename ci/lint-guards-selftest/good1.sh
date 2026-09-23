#!/bin/sh
command -v patch >/dev/null || { echo "no patch"; exit 1; }
patch -p1 -f -i a.diff </dev/null
PY=$(command -v python3)
[ -n "$PY" ] || { echo "no python3"; exit 1; }
"$PY" -c 'import six'
