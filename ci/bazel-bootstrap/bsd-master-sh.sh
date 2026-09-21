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
FreeBSD|GhostBSD)
	env ASSUME_ALWAYS_YES=yes pkg install -y openjdk25 zip unzip python3 bash git patch
	JAVA_HOME=/usr/local/openjdk25 ;;
OpenBSD)
	# jdk%25 は「stem が jdk で版が 25」。無印 jdk-25 は別の意味になる
	pkg_add -I jdk%25 zip unzip python3 bash git
	JAVA_HOME=/usr/local/jdk-25 ;;
*) echo "この OS の手当てを持っていない: $OS"; exit 1 ;;
esac
[ -x "$JAVA_HOME/bin/javac" ] || { echo "JDK 25 が $JAVA_HOME に無い"; ls -d /usr/local/*jdk* /usr/local/openjdk* 2>/dev/null; exit 1; }
export JAVA_HOME
# 作業場は広い所へ。VM の /var/tmp か /tmp
for d in /var/tmp /tmp; do [ -w "$d" ] && { WORK=$d/master-sh; break; }; done
export WORK
SH_BIN=/bin/sh LOG_BASH=${LOG_BASH:-1} NO_VIS=${NO_VIS:-1} \
	sh "$GITHUB_WORKSPACE/ci/bazel-bootstrap/bootstrap-dist-sh.sh" "$DIST"
