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
# bash が package 由来なら、何がそれを要求しているかを出す (base か後入れかの区別)
if command -v pkg_info >/dev/null 2>&1 && pkg_info -e bash >/dev/null 2>&1; then
  echo "PKG|$name|$(pkg_info -e bash)|required-by: $(pkg_info -qR bash 2>/dev/null | tr '\n' ' ')|automatic=$(pkg_info -Q automatic bash 2>/dev/null)"
elif command -v pkg >/dev/null 2>&1 && pkg info -e bash 2>/dev/null; then
  echo "PKG|$name|$(pkg query '%n-%v' bash)|required-by: $(pkg query '%rn' bash | tr '\n' ' ')|automatic=$(pkg query '%a' bash)"
fi
