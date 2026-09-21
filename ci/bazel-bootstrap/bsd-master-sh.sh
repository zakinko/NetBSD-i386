#!/bin/sh
# BSD の VM の中で走る。JDK 25 と道具を入れて、workspace に置かれた dist を
# /bin/sh だけで bootstrap する (bootstrap-dist-sh.sh を呼ぶ)。
#
# 使い方: bsd-master-sh.sh <dist.zip>   (GITHUB_WORKSPACE が要る)
set -eu
DIST=$1
OS=$(uname -s)
echo "### $OS $(uname -r)  /bin/sh は $(/bin/sh -c 'echo $0'; ls -l /bin/sh | sed 's/.* -> //')"
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD)
	env ASSUME_ALWAYS_YES=yes pkg install -y openjdk25 zip unzip python3 bash git patch
	JAVA_HOME=/usr/local/openjdk25 ;;
MidnightBSD)
	# mports には bazel が無いが openjdk25 は在る。道具は mport で入れる。
	mport install -y openjdk25 zip unzip python3 bash git patch || mport install openjdk25 zip unzip python3 bash git patch
	JAVA_HOME=/usr/local/openjdk25 ;;
OpenBSD)
	# jdk%25 は「stem が jdk で版が 25」。無印 jdk-25 は別の意味になる
	# OpenBSD の package は flavor 付きで、python3 は python%3、unzip は
	# unzip-- と書く。ci/bazel-bsd/run.sh が踏んだ罠と同じ。
	pkg_add -I jdk%25 zip bash git
	pkg_add -I 'python%3'
	pkg_add -I unzip-- || pkg_add -I unzip
	JAVA_HOME=/usr/local/jdk-25 ;;
*) echo "この OS の手当てを持っていない: $OS"; exit 1 ;;
esac
[ -x "$JAVA_HOME/bin/javac" ] || { echo "JDK 25 が $JAVA_HOME に無い"; ls -d /usr/local/*jdk* /usr/local/openjdk* 2>/dev/null; exit 1; }
export JAVA_HOME
if ! "$JAVA_HOME/bin/javac" -version >/dev/null 2>&1; then
	# HardenedBSD では package の javac が libjli.so を見つけられなかった
	# (run 35611323359)。何が違うのかを箱に言わせてから、LD_LIBRARY_PATH で
	# 越えられるかを試す。越えたとしてもそれは箱の設定の話で、sh 化の話ではない。
	echo "=== javac が起動しない。診断"
	"$JAVA_HOME/bin/javac" -version 2>&1 | head -3 || true
	ldd "$JAVA_HOME/bin/javac" 2>&1 | head -8 || true
	readelf -d "$JAVA_HOME/bin/javac" 2>/dev/null | grep -i 'rpath\|runpath\|origin' || true
	sysctl -a 2>/dev/null | grep -i 'hardening\|pax' | head -12 || true
	ls -l /proc 2>/dev/null | head -2 || true
	LD_LIBRARY_PATH="$JAVA_HOME/lib:$JAVA_HOME/lib/server"; export LD_LIBRARY_PATH
	if "$JAVA_HOME/bin/javac" -version >/dev/null 2>&1; then
		echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH で起動した"
	else
		echo "LD_LIBRARY_PATH でも起動しない"; exit 1
	fi
fi
# 作業場は広い所へ。VM の /var/tmp か /tmp
for d in /var/tmp /tmp; do [ -w "$d" ] && { WORK=$d/master-sh; break; }; done
export WORK
SH_BIN=/bin/sh LOG_BASH=${LOG_BASH:-1} NO_VIS=${NO_VIS:-1} \
	sh "$GITHUB_WORKSPACE/ci/bazel-bootstrap/bootstrap-dist-sh.sh" "$DIST"
