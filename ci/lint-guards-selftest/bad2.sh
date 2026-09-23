#!/bin/sh
PY=$(command -v python3)
"$PY" -c 'import six'
[ -n "$PY" ] || { echo "no python3"; exit 1; }
