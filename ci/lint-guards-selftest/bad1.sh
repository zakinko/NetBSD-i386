#!/bin/sh
patch -p1 -f -i a.diff </dev/null
command -v patch >/dev/null || { echo "no patch"; exit 1; }
