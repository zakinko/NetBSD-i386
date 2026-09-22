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
	pkg install -y python3 ninja git gmake pkgconf || pkg install -y python3 ninja git gmake pkgconf ;;
MidnightBSD)
	mport install -y python3 ninja git gmake pkgconf || mport install python3 ninja git gmake pkgconf ;;
DragonFly)
	pkg install -y python3 ninja git gmake pkgconf ;;
NetBSD)
	/usr/sbin/pkg_add -U pkgin || true
	pkgin -y install python313 ninja-build git-base gmake pkg-config
	ln -sf /usr/pkg/bin/python3.13 /usr/pkg/bin/python3
	PATH=/usr/pkg/bin:/usr/pkg/sbin:$PATH; export PATH ;;
OpenBSD)
	pkg_add -I python%3 ninja git gmake pkgconf || true
	ln -sf /usr/local/bin/python3 /usr/local/bin/python 2>/dev/null || true ;;
Linux)
	if [ -f /etc/os-release ]; then
		ID=$(. /etc/os-release; echo "${ID:-}")
	fi
	case "${ID:-}" in
	debian|ubuntu) apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3 ninja-build git g++ make pkg-config ;;
	alpine) apk add --no-cache python3 ninja-build git g++ make pkgconf bash ;;
	*) echo "この distro の入れ方を持っていない: ${ID:-}"; exit 1 ;;
	esac ;;
*) echo "この OS の手当てを持っていない: $OS"; exit 1 ;;
esac

echo "=== mozc $MOZC_TAG を取る"
git clone -q --depth 1 -b "$MOZC_TAG" https://github.com/google/mozc.git mozc
cd mozc
git submodule update --init --recursive --depth 1 -- src/third_party/gyp 2>/dev/null \
	|| git submodule update --init --recursive --depth 1 || true
cd src
echo "=== third_party の中身"; ls third_party 2>/dev/null | head

PY=$(command -v python3 || command -v python)
[ -n "$PY" ] || { echo "python3 が無い"; exit 1; }
"$PY" --version

echo "=== gyp"
"$PY" build_mozc.py gyp --noqt 2>&1 | tail -20

echo "=== build"
TARGETS=${TARGETS:-"server/server.gyp:mozc_server unix/emacs/emacs.gyp:mozc_emacs_helper"}
# shellcheck disable=SC2086
# --no_ibus_build と --no_gtk_build は 2.29 の doc の話で、3.33 の
# build_mozc.py には無い ("no such option")。build 側が取るのは -c と
# --target_platform ほか数個だけ
if "$PY" build_mozc.py build -c Release $TARGETS 2>&1 | tail -40; then
	echo "=== 出来た物"
	ls -l out_linux/Release out_bsd/Release 2>/dev/null | head -20
	for f in out_linux/Release/mozc_server out_bsd/Release/mozc_server \
		out_linux/Release/mozc_emacs_helper out_bsd/Release/mozc_emacs_helper; do
		[ -x "$f" ] && { echo "RESULT mozc-gyp $OS OK: $f"; file "$f" 2>/dev/null || true; }
	done
else
	echo "RESULT mozc-gyp $OS NG"
	exit 1
fi
