#!/bin/sh
# mozc を GYP で建てる。bazel を通さずに、どの port でどこまで行くかを見る。
#
# なぜ GYP か。mozc の master は 2026-03-11 の 0e55551e で gyp の file を全部
# 消しており、今の木は bazel しか持たない。bazel は BSD で踏み台から建てる
# ところまで手当てが要る (このリポジトリのもう一つの仕事) が、GYP なら
# python3 と ninja と protobuf と compiler だけで建つので、port の側の問題と
# build system の側の問題を分けて見られる。
#
# 版は gyp が残っている最後のあたりを使う (既定 3.33.6089、2026-01-28)。
#
#   MOZC_TAG   建てる tag (既定 3.33.6089)
#   TARGETS    build_mozc.py へ渡す target (既定 server と emacs helper)
#
# 出来た binary を動かすところまではここではしない。まず「建つか」を測る。
set -eu

CI_DIR=$(cd "$(dirname "$0")" && pwd)

MOZC_TAG=${MOZC_TAG:-3.33.6089}
OS=$(uname -s)
echo "=== $OS $(uname -r) $(uname -m)  mozc $MOZC_TAG"

# 作業場は広い所へ (NetBSD の像は / が小さい)
WORK=""
best=0
for d in /var/tmp /tmp "$HOME"; do
	[ -w "$d" ] || continue
	free=$(df -k "$d" 2>/dev/null | awk 'NR==2 {print $4}')
	case "$free" in ''|*[!0-9]*) continue ;; esac
	[ "$free" -gt "$best" ] && { best=$free; WORK=$d/mozc-gyp; }
done
[ -n "$WORK" ] || { echo "書ける作業場が無い"; exit 1; }
echo "作業場: $WORK ($((best / 1024)) MB 空き)"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

echo "=== 道具を入れる"
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD)
	pkg install -y python3 py311-six ninja git gmake pkgconf || pkg install -y python3 py312-six ninja git gmake pkgconf ;;
MidnightBSD)
	mport install -y python3 py311-six ninja git gmake pkgconf || mport install python3 ninja git gmake pkgconf ;;
DragonFly)
	pkg install -y python3 py311-six ninja git gmake pkgconf
	# base の gcc は 8 で concept を持たない (mozc 3.33 は C++20 が要る)。
	# dports の gcc を使う。libstdc++ もその版の物が付いてくるので、
	# clang + 古い libstdc++ の組み合わせを避けられる
	for v in 14 13 12; do
		pkg install -y "gcc$v" && break
	done
	CXX_BIN=$(ls /usr/local/bin/g++[0-9][0-9] 2>/dev/null | sort -V | tail -1)
	CC_BIN=$(ls /usr/local/bin/gcc[0-9][0-9] 2>/dev/null | sort -V | tail -1)
	[ -n "$CXX_BIN" ] || { echo "dports の g++ が見つからない"; ls /usr/local/bin/g[c+][c+]* 2>/dev/null | head; exit 1; }
	# gyp の ninja generator は target 用に CC/CXX、host 用に CC_host/CXX_host を
	# 見る (chromium/gyp の pylib/gyp/generator/ninja.py:2022)。host 側が空なら
	# target の物に落ちるが、明示しておく
	CC=$CC_BIN; CXX=$CXX_BIN; CC_host=$CC_BIN; CXX_host=$CXX_BIN
	export CC CXX CC_host CXX_host
	echo "DragonFly の compiler: $CXX ($("$CXX" --version | head -1))" ;;
NetBSD)
	/usr/sbin/pkg_add -U pkgin || true
	pkgin -y install python313 py313-six ninja-build git-base gmake pkg-config
	ln -sf /usr/pkg/bin/python3.13 /usr/pkg/bin/python3
	PATH=/usr/pkg/bin:/usr/pkg/sbin:$PATH; export PATH ;;
OpenBSD)
	pkg_add -I python%3 py3-six ninja git gmake pkgconf || true
	ln -sf /usr/local/bin/python3 /usr/local/bin/python 2>/dev/null || true ;;
Linux)
	if [ -f /etc/os-release ]; then
		ID=$(. /etc/os-release; echo "${ID:-}")
	fi
	case "${ID:-}" in
	debian|ubuntu) apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3 python3-six ninja-build git g++ make pkg-config ;;
	alpine) apk add --no-cache python3 py3-six ninja-build git g++ make pkgconf bash ;;
	*) echo "この distro の入れ方を持っていない: ${ID:-}"; exit 1 ;;
	esac ;;
*) echo "この OS の手当てを持っていない: $OS"; exit 1 ;;
esac

echo "=== mozc $MOZC_TAG を取る"
git clone -q --depth 1 -b "$MOZC_TAG" https://github.com/google/mozc.git mozc
cd mozc
# submodule は abseil / protobuf / gyp などで、無いと ninja が source を
# 見つけられない (run 35794480006 の Ubuntu: exponential_biased.cc が missing)。
# 落ちたらそこで止める
git submodule update --init --recursive --depth 1
cd src
echo "=== third_party の中身"; ls third_party 2>/dev/null | head

# BSD では build_mozc.py が target_platform を決められない
# ("Unknown target_platform: None")。五つの BSD を教える
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|NetBSD|OpenBSD|DragonFly)
	echo "=== BSD の当て物"
	patch -p1 -f -i "$CI_DIR/bsd-build_mozc.patch" </dev/null
	# port.h は最初に当たる壁 ("Unsupported target platform.")。build の
	# 側が通ってから出るので、先に入れておく
	patch -p1 -f -i "$CI_DIR/bsd-port-h.patch" </dev/null
	# ipc/unix_ipc.cc は struct ucred と SO_PEERCRED (Linux の綴り) を使う。
	# BSD には無いので compile で落ちる。長さを sizeof(sun_family) で作って
	# いる所も、sun_len を持つ BSD では一文字足りない
	patch -p1 -f -i "$CI_DIR/bsd-unix-ipc.patch" </dev/null
	# GetServerDirectory() は Windows / macOS / Linux / WASM しか名乗らず、
	# 当たらないと戻り値が無くて compile が落ちる (source の註がそう言って
	# いる)。BSD は Linux と同じ所へ入れる
	patch -p1 -f -i "$CI_DIR/bsd-system-util.patch" </dev/null
	# cpu_stats.cc も三箇所で Windows / macOS / Linux しか名乗らない
	patch -p1 -f -i "$CI_DIR/bsd-cpu-stats.patch" </dev/null
	# IsValidServer() は /proc/<pid>/exe を読む。FreeBSD は procfs を mount
	# せず、NetBSD は noauto なので、そこは飛ばされて server path が空のまま
	# 照合に落ちる (compile は通るので、煙試験まで行って初めて出る)
	patch -p1 -f -i "$CI_DIR/bsd-ipc-path.patch" </dev/null ;;
esac

PY=$(command -v python3 || command -v python)
# gyp の pylib は six を import する。package 名が箱ごとに違ううえ、無い箱も
# あるので、届かなければその場で確かめてから進む
if ! "$PY" -c 'import six' 2>/dev/null; then
	echo "six が無い。gyp は import gyp で落ちる"
	"$PY" -m pip install --break-system-packages six 2>/dev/null \
		|| "$PY" -m pip install --user six 2>/dev/null \
		|| { echo "six を入れられない"; exit 1; }
fi
[ -n "$PY" ] || { echo "python3 が無い"; exit 1; }
"$PY" --version

[ -n "${CXX:-}" ] && echo "CC=$CC CXX=$CXX で建てる"

echo "=== gyp"
# pipe に繋ぐと gyp の失敗が tail の成功に化ける (FreeBSD で実際にそうなり、
# 次の build まで進んでから "Unknown target_platform: None" で落ちた)。
# file に落として、落ちたらそこで止める
if ! "$PY" build_mozc.py gyp --noqt > gyp.log 2>&1; then
	echo "RESULT mozc-gyp $OS NG (gyp)"; tail -30 gyp.log; exit 1
fi
tail -5 gyp.log

echo "=== build"
TARGETS=${TARGETS:-"server/server.gyp:mozc_server unix/emacs/emacs.gyp:mozc_emacs_helper"}
# shellcheck disable=SC2086
# --no_ibus_build と --no_gtk_build は 2.29 の doc の話で、3.33 の
# build_mozc.py には無い ("no such option")。build 側が取るのは -c と
# --target_platform ほか数個だけ
if "$PY" build_mozc.py build -c Release $TARGETS > build.log 2>&1; then
	echo "=== 出来た物"
	ls -l out_linux/Release out_bsd/Release 2>/dev/null | head -20
	n=0
	for f in out_linux/Release/mozc_server out_bsd/Release/mozc_server \
		out_linux/Release/mozc_emacs_helper out_bsd/Release/mozc_emacs_helper; do
		if [ -x "$f" ]; then
			echo "RESULT mozc-gyp $OS OK: $f"
			file "$f" 2>/dev/null || true
			n=$((n + 1))
		fi
	done
	[ "$n" -ge 2 ] || { echo "RESULT mozc-gyp $OS NG: binary が $n 個しか出ていない"; exit 1; }
	# 建っただけでは IPC の腕を踏まない。helper の protocol を直に叩いて
	# 「にほんご」を変換させ、候補に 日本語 が出るところまで見る。
	# root では base/run_level.cc が拒むので、smoke.sh が一般 user を作る
	OUTDIR=""
	for d in out_bsd/Release out_linux/Release; do
		[ -x "$d/mozc_server" ] && { OUTDIR=$d; break; }
	done
	if [ -n "$OUTDIR" ] && [ "$(id -u)" = 0 ]; then
		echo "=== 煙試験 ($OUTDIR)"
		sh "$CI_DIR/smoke.sh" "$PWD/$OUTDIR" || echo "煙試験は通らなかった (建った事実は上の RESULT のとおり)"
	else
		echo "煙試験は飛ばす (root ではないか、binary の置き場が分からない)"
	fi
else
	echo "RESULT mozc-gyp $OS NG (build)"
	# ninja の FAILED の塊だけを出す。tail だけだと warning に埋もれて、
	# 何が落ちたのか log に残らない (run 35798811151 の FreeBSD と NetBSD)
	echo "--- FAILED の行と、その後ろ"
	grep -n -A25 '^FAILED:' build.log | head -80
	echo "--- error: の行"
	grep -n 'error:' build.log | head -20
	echo "--- 末尾"
	tail -20 build.log
	exit 1
fi
