#!/bin/sh
# 守りが、守る対象より後ろに置かれていないかを見る。
#
# 一日に二度これを書いた。patch(1) が在るかの検査が当て物を全部当てた後ろに
# 在り、python3 が在るかの検査が $PY を使った後ろに在った。どちらも「無い箱で
# だけ、原因と違う message を出して落ちる」形で、在る箱では一生出ない。
#
# 検査の形は二つだけ見る。
#
#	command -v X >/dev/null || { ...; exit }      X を使う前に在るか
#	[ -n "$V" ] || { ...; exit }                  $V を使う前に空でないか
#
# どちらも、その行より前に対象が使われていたら黙っていない。
set -u
rc=0
for f in "$@"; do
	[ -f "$f" ] || continue
	awk -v file="$f" '
	# command -v X ... || ... exit
	/command -v [A-Za-z0-9_.\/-]+/ && /\|\|/ && /exit/ {
		match($0, /command -v [A-Za-z0-9_.\/-]+/)
		tool = substr($0, RSTART + 11, RLENGTH - 11)
		guard[tool] = NR
	}
	# [ -n "$V" ] || ... exit
	/\[ -n "\$[A-Za-z_][A-Za-z0-9_]*" \]/ && /\|\|/ && /exit/ {
		match($0, /\$[A-Za-z_][A-Za-z0-9_]*/)
		v = substr($0, RSTART + 1, RLENGTH - 1)
		vguard[v] = NR
	}
	# package を入れている行は「使っている」ではない。道具の名前が
	# install の引数として並ぶだけなので、数えると偽陽性になる
	{
		# 語の頭で区切る。区切らないと import six の "mport " が
		# MidnightBSD の mport に当たって、行ごと捨ててしまう
		inst = ($0 ~ /(^|[^A-Za-z0-9_-])(pkg|pkgin|mport|apt-get|apk|dnf|yum|pacman|emerge|zypper|brew|pkg_add|xbps-install)[ \t]/)
		# 註は使用ではない。頭が # の行は丸ごと落とす
		cmt = ($0 ~ /^[ \t]*#/)
		line[NR] = (inst || cmt) ? "" : $0
	}
	END {
		for (t in guard) {
			for (i = 1; i < guard[t]; i++) {
				# 代入と、検査そのものの行は使用ではない
				if (line[i] ~ ("(^|[^A-Za-z0-9_.\\/-])" t "([^A-Za-z0-9_.\\/-]|$)") &&
				    line[i] !~ /command -v/ && line[i] !~ ("^[ \t]*" t "=")) {
					printf "%s:%d: %s の守りが %d 行目に在るが、ここで既に使っている\n", file, i, t, guard[t]
					bad = 1
					break
				}
			}
		}
		for (v in vguard) {
			for (i = 1; i < vguard[v]; i++) {
				if (line[i] ~ ("\\$\\{?" v "[^A-Za-z0-9_]") && line[i] !~ ("^[ \t]*" v "=")) {
					printf "%s:%d: $%s の守りが %d 行目に在るが、ここで既に使っている\n", file, i, v, vguard[v]
					bad = 1
					break
				}
			}
		}
		exit bad ? 1 : 0
	}' "$f" || rc=1
done
[ "$rc" = 0 ] && echo "守りの置き場: 問題なし ($# 本)"
exit "$rc"
