#!/bin/sh
H=$(getent passwd x | cut -d: -f6)
[ -n "$H" ] || H=$(awk -F: "\$1==\"x\"{print \$6}" /etc/passwd)
[ -n "$H" ] && [ -d "$H" ] || { echo "no home"; exit 1; }
echo "$H"
