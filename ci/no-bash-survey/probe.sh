#!/bin/sh
# 素の箱で bash の有無と /bin/sh の正体を一行で出す。何も入れずに走らせること。
name=$1
os=$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || uname -sr)
b=$(command -v bash 2>/dev/null); [ -n "$b" ] || b=none
for p in /bin/bash /usr/bin/bash /usr/local/bin/bash /usr/pkg/bin/bash; do
  [ -e "$p" ] && b="$b ($p)"
done
sh=$(ls -l /bin/sh 2>/dev/null | sed 's/.* \/bin\/sh/\/bin\/sh/')
real=$(readlink -f /bin/sh 2>/dev/null || echo -)
echo "SURVEY|$name|$os|bash=$b|$sh|real=$real"
