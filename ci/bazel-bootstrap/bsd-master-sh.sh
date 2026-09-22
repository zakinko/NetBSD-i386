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
NetBSD)
	# pkgsrc の openjdk21 は X の library に link されているので xbase を先に展開する
	# (ci/bazel-bsd/run.sh と同じ)。go は rules_go の SDK が NetBSD に無いので host の物。
	ftp -o /var/tmp/xbase.tar.xz "https://cdn.NetBSD.org/pub/NetBSD/NetBSD-$(uname -r)/$(uname -m)/binary/sets/xbase.tar.xz" \
		&& tar -C / -xf /var/tmp/xbase.tar.xz || echo "xbase が取れなかった"
	/usr/sbin/pkg_add -U pkgin
	pkgin -y install bash zip unzip python313 go126 git-base patch gtar
	ln -sf /usr/pkg/bin/python3.13 /usr/pkg/bin/python3
	PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/pkg/go126/bin:$PATH; export PATH
	if [ "${JDK_KIT:-}" = 1 ]; then
		# zakinko/jdk25u の bootstrap kit (NetBSD 10/11 amd64、170MB)。PaX の印を
		# paxctl +m で付けないと JIT が動かない。
		mkdir -p /usr/pkg/java/kit25
		ftp -o /var/tmp/kit25.tar.xz "https://github.com/zakinko/jdk25u/releases/download/bootstrap-kit-25-20260921/bootstrap-jdk-1.25.0.5.0-netbsd-10-amd64-20260921.tar.xz"
		tar -C /usr/pkg/java/kit25 --strip-components=1 -xf /var/tmp/kit25.tar.xz
		paxctl +m /usr/pkg/java/kit25/bin/* 2>/dev/null || true
		find /usr/pkg/java/kit25/lib -name '*.so' -exec paxctl +m {} \; 2>/dev/null || true
		JAVA_HOME=/usr/pkg/java/kit25
	else
		pkgin -y install openjdk21
		JAVA_HOME=/usr/pkg/java/openjdk21
		JAVA_VERSION=21; export JAVA_VERSION
	fi ;;
DragonFly)
	pkg install -y git bash zip unzip python3 go curl patch
	pkg install -y openjdk21 || true
	JAVA_HOME=/usr/local/openjdk21
	JAVA_VERSION=21; export JAVA_VERSION ;;
*) echo "この OS の手当てを持っていない: $OS"; exit 1 ;;
esac
[ -x "$JAVA_HOME/bin/javac" ] || { echo "JDK 25 が $JAVA_HOME に無い"; ls -d /usr/local/*jdk* /usr/local/openjdk* 2>/dev/null; exit 1; }
export JAVA_HOME
# HardenedBSD の uname -s は FreeBSD を返す (mozc の煙試験も FreeBSD と名乗った)。
# 名前ではなく kern.features.hbsd_hardening で見分ける。
if [ "$(sysctl -n kern.features.hbsd_hardening 2>/dev/null)" = 1 ]; then
	# hardening.harden_rtld=1 が、JDK の RUNPATH ($ORIGIN:$ORIGIN/../lib) を
	# "Tainted process refusing to run binary" で拒む (run 35616309433)。
	# 箱の設定なので、試験の箱では外す。LD_LIBRARY_PATH では越えられなかった。
	sysctl hardening.harden_rtld=0
	# その先で JVM が CodeHeap を確保できない。PaX の MPROTECT が JIT の W^X を
	# 拒む (mozc の CI で確かめた)。試験の箱では外す。
	sysctl hardening.pax.mprotect.status=0 || true
	sysctl hardening.pax.pageexec.status=0 || true
fi
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
SH_BIN=/bin/sh LOG_BASH=${LOG_BASH:-1} NO_VIS=${NO_VIS:-0} \
	sh "$GITHUB_WORKSPACE/ci/bazel-bootstrap/bootstrap-dist-sh.sh" "$DIST"
