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
	JAVA_HOME=/usr/local/openjdk25
	# rules_java の local_jdk は MidnightBSD を知らず、include/linux の
	# jni_md.h を写そうとして落ちる (run 35730047335)。package は FreeBSD 向けの
	# build なので include/freebsd が正。そこへ向ける
	[ -e "$JAVA_HOME/include/linux" ] || ln -s freebsd "$JAVA_HOME/include/linux" ;;
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
	# 取れたかどうかを、rc ではなく入った物で言う。ここで落ちても止めないのは
	# kit を使うときに X が要るとは限らないからだが、後で openjdk が library を
	# 見つけられずに落ちたとき、原因がここだったのかを log で分けられるようにする
	if [ -e /usr/X11R7/lib/libX11.so ]; then
		echo "X sets: 在り (/usr/X11R7/lib/libX11.so)"
	else
		echo "X sets: 無し。pkgsrc の openjdk は X の library に link されているので、"
		echo "        JDK_KIT=0 のときはこの後 shared library が無いと言われる"
	fi
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
		rm -f /var/tmp/kit25.tar.xz
		paxctl +m /usr/pkg/java/kit25/bin/* 2>/dev/null || true
		find /usr/pkg/java/kit25/lib -name '*.so' -exec paxctl +m {} \; 2>/dev/null || true
		# kit は BSD port の作りで jni_md.h が include/bsd/ に在る。pkgsrc の
		# openjdk は include/netbsd/ に置き、build_unix_jni.sh と rules_java の
		# 当て物はそちらを指す。当て物を kit に合わせて曲げず、kit を pkgsrc の
		# 形に見せる。
		ln -s bsd /usr/pkg/java/kit25/include/netbsd
		JAVA_HOME=/usr/pkg/java/kit25
	else
		pkgin -y install openjdk21
		JAVA_HOME=/usr/pkg/java/openjdk21
		JAVA_VERSION=21; export JAVA_VERSION
	fi ;;
DragonFly)
	pkg install -y git bash zip unzip python3 go curl patch
	if [ "${JDK_KIT:-}" = 1 ]; then
		# dports は openjdk21 止まりで、master は 22 以上が要る。zakinko/jdk25u の
		# bootstrap kit (DragonFly 6.4 x86_64、cross build、174MB)。DragonFly に
		# PaX は無いので印は要らない。include は BSD port の作りで include/bsd/。
		curl -fsSL -o /var/tmp/kit25.tar.xz "https://github.com/zakinko/jdk25u/releases/download/bootstrap-kit-25-dragonfly-20260922/bootstrap-jdk-1.25.0.5.0-dragonfly-6.4-x86_64-20260922.tar.xz"
		# DragonFly の bsdtar は --strip-components 付きで "Error exit delayed
		# from previous errors" で落ちた (run 35692632379)。素に展開して mv する。
		# locale の警告 (Failed to set default locale) は LC_ALL=C で黙らせる。
		rm -rf /usr/local/kit25 /usr/local/bootstrap
		# macOS で固めた tar は xattr を運ぶ。DragonFly の bsdtar はそれを
		# 「復元できない」と言って rc=1 で終わる。--no-xattrs で無視させる
		# (release の tarball 自体も xattr 無しで作り直した)
		LC_ALL=C tar --no-xattrs -C /usr/local -xf /var/tmp/kit25.tar.xz || { echo "kit の展開に失敗"; ls -la /usr/local/bootstrap 2>&1 | head; exit 1; }
		mv /usr/local/bootstrap /usr/local/kit25
		rm -f /var/tmp/kit25.tar.xz
		# dports の openjdk は include/freebsd を include/dragonfly に写して置く。
		# kit は include/bsd/ なので、NetBSD の kit と同じく symlink で dports の
		# 形に見せる (build_unix_jni の当て物は dports の形を指す)。
		ln -s bsd /usr/local/kit25/include/dragonfly
		JAVA_HOME=/usr/local/kit25
	else
		pkg install -y openjdk21 || true
		JAVA_HOME=/usr/local/openjdk21
		JAVA_VERSION=21; export JAVA_VERSION
	fi ;;
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
# aarch64 の箱は x86_64 の runner で TCG (全命令 emulation) で動いている。
# そこで JDK 25 の javac が SIGSEGV (pc=0) で落ちた (run 35676218786、
# FreeBSD 15.1 aarch64)。実機ではなく emulation の側の問題と見て、JIT を C1
# だけにし、SVE を切って試す。効いたとしても「aarch64 で建つ」ではなく
# 「TCG の下でも建つ」と読む。hs_err は失敗時に bootstrap-dist-sh.sh が出す。
case "$(sysctl -n hw.machine 2>/dev/null)$(uname -m)" in
*arm64*|*aarch64*|*evbarm*)
	if [ "$(sysctl -n kern.vm_guest 2>/dev/null)" != none ]; then
		JAVA_TOOL_OPTIONS="-XX:TieredStopAtLevel=1 -XX:UseSVE=0"; export JAVA_TOOL_OPTIONS
		echo "aarch64 の VM: JAVA_TOOL_OPTIONS=$JAVA_TOOL_OPTIONS"
	fi ;;
esac
# 作業場は広い所へ。書ける dir のうち一番空いている所を選ぶ。NetBSD の像は
# / が小さく、link の途中で "No space left on device" になった
# (run 35757966151)。選んだ理由が後から読めるように df を出す。
echo "=== 空き"; df -k / /var/tmp /tmp /usr 2>/dev/null || df -k
WORK=""
best=0
for d in /var/tmp /tmp /usr/tmp; do
	[ -w "$d" ] || continue
	free=$(df -k "$d" 2>/dev/null | awk 'NR==2 {print $4}')
	case "$free" in ''|*[!0-9]*) continue ;; esac
	if [ "$free" -gt "$best" ]; then best=$free; WORK=$d/master-sh; fi
done
[ -n "$WORK" ] || { echo "書ける作業場が無い"; exit 1; }
echo "作業場: $WORK ($((best / 1024)) MB 空き)"
# bazel の output base と TMPDIR も同じ所へ。既定は /tmp で、NetBSD の像では
# そこが小さい。buildenv.sh は BAZEL_WRKDIR を見て両方をその下へ向ける
BAZEL_WRKDIR=$WORK/bazel-wrk; export BAZEL_WRKDIR
export WORK
SH_BIN=/bin/sh LOG_BASH=${LOG_BASH:-1} NO_VIS=${NO_VIS:-0} \
	sh "$GITHUB_WORKSPACE/ci/bazel-bootstrap/bootstrap-dist-sh.sh" "$DIST"
