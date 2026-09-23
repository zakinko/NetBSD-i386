#!/bin/sh
# 建てた mozc_server と mozc_emacs_helper を実際に動かす。helper の protocol を
# 直に叩いて「にほんご」を変換させ、候補に 日本語 が出るところまで見る。
#
# 建っただけでは IPC の腕は踏めない。client が unix socket で server に繋ぎ、
# peer の資格情報を確かめ、server の path を照合する — この PR が触るのは
# 全部そこで、変換が返って初めて通ったと言える。
#
# root では測れない。base/run_level.cc が geteuid() == 0 を拒み、その応答は
# server が無いときと一字一句同じ ((error . session-error)) なので、一般 user を
# 作って叩く。
#
# 使い方: smoke.sh <binary の在る dir>
#
# GYP で建てた物にも bazel で建てた物にも使う。渡された dir の直下に
# mozc_server と mozc_emacs_helper が在ることを期待する (bazel なら
# server/ と unix/emacs/ の下なので、呼ぶ側で揃えてから渡す)。
set -eu
BIN=$1
OS=$(uname -s)

# helper は /usr/lib/mozc/mozc_server を起動する (base/system_util.cc の
# kMozcServerDir の既定)。そこへ置く。
mkdir -p /usr/lib/mozc
# helper の置き場も作る。Linux と FreeBSD と OpenBSD には元から在るが、
# NetBSD は package が /usr/pkg に入るので /usr/local が無い。cp が
# "No such file or directory" で落ちて、煙試験が移植の欠陥に見えた
# (run 35847538625 の netbsd)
mkdir -p /usr/local/bin
for f in "$BIN/server/mozc_server" "$BIN/mozc_server"; do
	[ -x "$f" ] && { cp "$f" /usr/lib/mozc/mozc_server; break; }
done
for f in "$BIN/unix/emacs/mozc_emacs_helper" "$BIN/mozc_emacs_helper"; do
	[ -x "$f" ] && { cp "$f" /usr/local/bin/mozc_emacs_helper; break; }
done
[ -x /usr/lib/mozc/mozc_server ] || { echo "mozc_server が $BIN に無い"; ls "$BIN" | head; exit 1; }
[ -x /usr/local/bin/mozc_emacs_helper ] || { echo "mozc_emacs_helper が $BIN に無い"; exit 1; }
chmod 755 /usr/lib/mozc/mozc_server /usr/local/bin/mozc_emacs_helper

U=mozcsmoke
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|DragonFly) pw useradd "$U" -m -s /bin/sh 2>/dev/null || true ;;
*) useradd -m -s /bin/sh "$U" 2>/dev/null || true ;;
esac
id "$U"

# n i h o n g o を一打ずつ、最後に space で変換。(EVENT_ID SendKey SESSION_ID KEY)
# の KEY は ASCII code か key symbol。入出力は user の home に置く。
H=$(eval echo "~$U")
IN=$H/smoke-in; OUT=$H/smoke-out; ERR=$H/smoke-err
{
	echo '(1 CreateSession)'
	n=2
	for k in 110 105 104 111 110 103 111 32; do
		echo "($n SendKey 1 $k)"; n=$((n+1))
	done
	echo "($n DeleteSession 1)"
} > "$IN"
chown "$U" "$IN"
rm -f "$OUT" "$ERR"
# profile は $HOME/.config/mozc (XDG_CONFIG_HOME が無ければ)。親の dir が
# 無いと server が起動できず、返るのは server が無いときと同じ
# (error . session-error) なので、原因を取り違えないよう先に作っておく。
# bazel 側の煙試験で一度これに引っかかっている
su -l "$U" -c "mkdir -p \$HOME/.config" || true
su -l "$U" -c "/usr/local/bin/mozc_emacs_helper < $IN > $OUT 2> $ERR" || true
echo "=== helper の応答 ($(wc -l < "$OUT" | tr -d ' ') 行)"
cut -c1-300 "$OUT"
echo "=== stderr"; head -20 "$ERR"
if grep -q '日本語' "$OUT"; then
	echo "RESULT mozc-smoke $OS OK: にほんご を変換して 日本語 が候補に出た"
else
	echo "RESULT mozc-smoke $OS NG: 日本語 が出ない"
	if grep -q 'session-error' "$OUT"; then
		echo '  (session-error: server に繋げていない。IPC か run_level)'
	fi
	exit 1
fi
