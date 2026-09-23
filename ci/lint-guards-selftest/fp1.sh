#!/bin/sh
GL=$(pkg_info -L x | head -1)
echo "libstdc++: ${GL:-(見つからない)}"
[ -n "$GL" ] || { echo "no"; exit 1; }
