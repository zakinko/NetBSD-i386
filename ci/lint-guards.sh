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

# 自己試験を先に走らせる。落ちるはずの二本と、通るはずの四本。ここが
# 合わなければ検査そのものが壊れているので、結果を出さずに止める。
# 一日でこれに三度救われた — awk の brace を壊したとき、mport が
# "import six" に当たっていたとき、そして入力 file を後始末で消していて
# 三本とも緑を返したとき
SELF=$(dirname "$0")/lint-guards-selftest
if [ "${LINT_GUARDS_SELFTEST:-1}" = 1 ] && [ -d "$SELF" ]; then
	for t in bad1 bad2; do
		LINT_GUARDS_SELFTEST=0 sh "$0" "$SELF/$t.sh" >/dev/null 2>&1 \
			&& { echo "自己試験: $t.sh を見逃した。検査が壊れている"; exit 2; }
	done
	for t in good1 fp1 fp2 fp3 fp4; do
		LINT_GUARDS_SELFTEST=0 sh "$0" "$SELF/$t.sh" >/dev/null 2>&1 \
			|| { echo "自己試験: $t.sh を誤って赤にした。検査が壊れている"; exit 2; }
	done
fi

rc=0
for f in "$@"; do
	# 無い file を黙って飛ばすと、検査が緑になった理由が「問題なし」なのか
	# 「見ていない」なのか分からなくなる。実際、自己試験の入力を消したあとに
	# 三本とも緑を返した
	[ -f "$f" ] || { echo "$f が無い"; rc=1; continue; }
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
	# heredoc の中は別の scope。<<WORD の在る行そのものは外側で、中身は
	# 次の行から。終端語の行で戻る
	{
		if (depth > 0 && $0 == term[depth]) {
			depth--
			scope[NR] = depth
		} else {
			scope[NR] = depth
			if (match($0, /<<-?["'"'"']?[A-Za-z_][A-Za-z0-9_]*/)) {
				w = substr($0, RSTART, RLENGTH)
				sub(/^<<-?["'"'"']?/, "", w)
				depth++
				term[depth] = w
			}
		}
	}
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
			# 守りの直前の代入より後ろだけを見る。同じ名前を別の物に
			# 使い回している script が在り、前半の V と後半の V は別物
			from = 1
			# 代入は行頭とは限らない。`[ -n "$V" ] || V=...` のような
			# fallback は、同じ行で見てから代入している。行頭だけを
			# 代入と見ると、この形を「守る前に使った」と誤って言う
			for (i = 1; i < vguard[v]; i++)
				if (line[i] ~ ("(^|[^A-Za-z0-9_])" v "=[^=]")) from = i + 1
			for (i = from; i < vguard[v]; i++) {
				# heredoc の中と外は別の scope
				if (scope[i] != scope[vguard[v]]) continue
				# ${V:-...} は「無ければ既定」で、守られていない使用ではない
				if (line[i] ~ ("[$]{" v "[:-]")) continue
				if (line[i] ~ ("[$]{?" v "[^A-Za-z0-9_]") &&
				    line[i] !~ ("(^|[^A-Za-z0-9_])" v "=[^=]")) {
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
