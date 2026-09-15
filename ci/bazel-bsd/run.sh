#!/bin/sh
# bazel の upstream master を BSD の中で、踏み台なしに建てる。
#
# 「踏み台なし」は、その機械に bazel が一つも無い状態から始める、という
# 意味である。配られている bazel を持ち込むと、BSD で何が足りないかが
# 見えなくなる。
#
#	bootstrap  9.2.0 の dist から bazel を建てるところまで。数十分
#	master     その bazel で upstream master を建てる。数時間
#
# 手当ては全部 zakinko/bazel の probe/plain-upstream の ci/ に在る。ここに
# 写さない。あちらが唯一の正で、ここはそれを VM の中から呼ぶだけである。
# 写しを二つ持つと、片方だけ直した状態が必ず出来る。
#
#	ci/bsd-bootstrap.sh    dist に枝の変更を被せて bootstrap する
#	ci/master-build.sh     master を建てる。三つの toolchain の壁の手当て込み
#
# その三つの壁は、どれも「BSD 向けの配布物が無い」という同じ形である。
#
#	rules_java    remote JDK に BSD 向けが無い
#	              → BUILD の remotejdk_25 を current_java_runtime にする
#	rules_python  配られる CPython に BSD 向けが無い
#	              → pip の hub を落とし、runtime_env_toolchains を足す
#	java_tools    同上
#
# 使い方:
#	sh ci/bazel-bsd/run.sh [bootstrap|master]
set -eu

STAGE=${1:-bootstrap}
BRANCH=${BRANCH:-probe/plain-upstream}
REPO=${REPO:-https://github.com/zakinko/bazel.git}

say() { echo "RESULT $*"; }

# / が小さい VM が在るので、木も work も一番広い所に置く。bazel の build は
# 出力だけで数 GB になる。
W=""
for d in /home /usr/home /var/tmp /usr/obj; do
	if [ -d "$d" ] && [ -w "$d" ]; then W="$d/bzbsd"; break; fi
done
[ -n "$W" ] || W="$HOME/bzbsd"
mkdir -p "$W"
W=$(cd "$W" && pwd -P)

OS=$(uname -s)
echo "### $OS  作業場 $W  段 $STAGE"
uname -a
df -h "$W" | tail -1

##### 1. 要るものを入れる #####
# 版を固定しない。どの BSD でも「入っている JDK のうち一番新しいもの」を
# 使う形にしてあるので (master-build.sh の current_java_runtime)、package の
# 版が上がっても script を追う必要が無い。
echo '##### 1. 依存を入れる #####'
case "$OS" in
NetBSD)
	REL=$(uname -r | cut -d_ -f1)
	ARCH=$(uname -m)
	# 配られている openjdk21 は X のライブラリに link されているので、X sets の
	# 無い箱では pkg_add が
	#
	#	missing required library: /usr/X11R7/lib/libX11.so.7
	#	Please make sure to install the X sets
	#
	# で落ちる。JDK は headless にしか使わないのに要る。sets を先に入れる。
	# 名前は xbase と xcomp、拡張子は .tar.xz (.tgz ではない)、path の arch は
	# uname -m (amd64) であって uname -p (x86_64) ではない。二度とも間違えた。
	if [ ! -f /usr/X11R7/lib/libX11.so.7 ]; then
		SETS="https://cdn.NetBSD.org/pub/NetBSD/NetBSD-$REL/$ARCH/binary/sets"
		for s in xbase xcomp; do
			echo "--- $s.tar.xz を入れる"
			if ftp -o "$W/$s.tar.xz" "$SETS/$s.tar.xz"; then
				(cd / && xzcat "$W/$s.tar.xz" | tar -xpf -)
			else
				say "$s.tar.xz が取れなかった ($SETS)"
			fi
			rm -f "$W/$s.tar.xz"
		done
	fi
	export PKG_PATH="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$ARCH/$REL/All"
	for p in git-base bash python313 unzip zip go; do
		pkg_add -U "$p" || say "pkg_add $p が入らなかった"
	done
	# 21 を採る。JDK 23 から annotation processing が既定で走らないので、
	# bazel 9.2.0 の bootstrap は 25 では建たない (上の JAVA_HOME の註)。
	pkg_add -U openjdk21 || say "JDK の package が入らなかった"
	;;
FreeBSD|GhostBSD)
	env ASSUME_ALWAYS_YES=yes pkg install -y git bash openjdk21 python3 unzip zip go || true
	;;
DragonFly)
	pkg install -y git bash openjdk21 python3 unzip zip go || true
	;;
OpenBSD)
	export PKG_PATH="https://cdn.openbsd.org/pub/OpenBSD/$(uname -r)/packages/$(uname -m)/"
	for p in git bash zip go; do
		pkg_add -I "$p" || say "pkg_add $p が入らなかった"
	done
	# 多版ある package は % で枝を指す。名前をそのまま渡すと
	#
	#	Can't find jdk-21
	#	Can't find python-3
	#
	# になる (jdk-21 は「stem が jdk で版がちょうど 21」の意味になる)。
	for j in 21 17 25; do
		if pkg_add -I "jdk%$j"; then echo "jdk%$j を入れた"; break; fi
	done
	for p in 3.13 3.12 3.11 3.10; do
		if pkg_add -I "python%$p"; then echo "python%$p を入れた"; break; fi
	done
	# flavour が複数あるものは -- で「flavour 無し」を指す。素の名前だと
	#
	#	Ambiguous: unzip could be unzip-6.0p18-iconv unzip-6.0p18
	#
	pkg_add -I unzip-- || pkg_add -I unzip || say "unzip が入らなかった"
	;;
*)
	say "知らない OS: $OS"
	exit 1
	;;
esac

# JDK の在処は OS ごとに違う。決め打ちせず、欲しい版から順に探す。
#
# 名前で sort してはいけない。openjdk8 は openjdk21 より後ろに並ぶので
# (文字として '8' > '2')、sort -r だと 8 を掴む。sort -V は NetBSD の sort に
# 無いことがある。欲しい順に名前を並べて、最初に javac が在るものを採る。
#
# **新しければよいわけではない。** 21 を先に探す。bootstrap は bazel 9.2.0 を
# -source 21 -target 21 で compile するが、JDK 23 から annotation processing が
# 既定で走らなくなったので、javac 25 で建てると AutoValue の生成 class が
# 出来ず
#
#	DependencyError.java:135: error: cannot find symbol
#	  symbol: variable AutoOneOf_DependencyError
#	... 178 errors
#
# で落ちる。OpenBSD 7.9 は jdk 25.0.2 を配っているので実際に踏んだ。
# BSD の話ではなく、bazel 9.2.0 と JDK 23+ の話である。
#
#	https://github.com/zakinko/NetBSD-i386/actions/runs/35012408515
JAVA_HOME=""
for n in 21 22 23 24 25 17; do
	for d in /usr/pkg/java/openjdk$n /usr/local/openjdk$n /usr/local/jdk-$n \
	         /usr/lib/jvm/java-$n-openjdk; do
		if [ -x "$d/bin/javac" ]; then JAVA_HOME=$d; break; fi
	done
	if [ -n "$JAVA_HOME" ]; then break; fi
done
# 名前が合わない置き方をしている箱のための最後の手 (版は問わない)。
if [ -z "$JAVA_HOME" ]; then
	for d in $(ls -d /usr/pkg/java/* /usr/local/openjdk* /usr/lib/jvm/* 2>/dev/null); do
		if [ -x "$d/bin/javac" ]; then JAVA_HOME=$d; break; fi
	done
fi
[ -n "$JAVA_HOME" ] || { say "JDK が見つからない"; exit 1; }
export JAVA_HOME
JAVA_VER=$("$JAVA_HOME/bin/javac" -version 2>&1 | sed 's/^javac //; s/\..*//')
export JAVA_VER
echo "JAVA_HOME=$JAVA_HOME  JAVA_VER=$JAVA_VER"

# python も同じ。drop_pip_dev_deps.py などがこれで走る。
for c in python3 python3.13 python3.12 python3.11; do
	if command -v "$c" >/dev/null 2>&1; then PY=$c; break; fi
done
[ -n "${PY:-}" ] || { say "python3 が見つからない"; exit 1; }
echo "python=$(command -v "$PY")"

# pkgsrc は python3.13 のような版つきの名前しか作らない。素の python3 を作る
# package も無い (repo に在るのは python310 から python314 まで)。ところが
# bazel の genrule は create_embedded_tools を #!/usr/bin/env python3 で起動し、
# action は env - で走るので、PATH に python3 という名前が無いと
#
#	src/BUILD:277:9: Executing genrule //src:embedded_tools_nojdk failed:
#	  (Exit 127): env: python3: No such file or directory
#
# で落ちる。1,479 action まで進んでから出るので手前の段では気づけない。
# 版つきの binary と同じ場所に張る。そこは command -v が見つけた以上 PATH に
# 在る。FreeBSD と OpenBSD は package が素の名前を作るので、その場合は飛ばす。
if ! command -v python3 >/dev/null 2>&1; then
	PYBIN=$(command -v "$PY")
	ln -sf "$PYBIN" "$(dirname "$PYBIN")/python3" || {
		say "python3 の名前を作れなかった"
		exit 1
	}
	echo "python3 -> $PYBIN を張った"
fi

# rules_go は SDK を自前で落とさず host の go を見る。
#
#	rules_go/go/private/sdk.bzl  _detect_host_sdk()
#	  GOROOT が在ればそれ、無ければ `go env GOROOT` を叩き、
#	  失敗すると fail("Could not detect host go version")
#
# bootstrap の段で既に要る (master-build.sh の go の扱いはその後の段にしか
# 効かない)。pkgsrc も dports も go を PATH に置かず /usr/pkg/go1NN や
# /usr/local/go1NN に入れるので、版の大きい方から探す。glob は昇順なので
# 素直に先頭を採ると一番古いものを掴む。
if ! command -v go >/dev/null 2>&1; then
	for d in $(ls -d /usr/pkg/go1* /usr/local/go1* /usr/local/go 2>/dev/null | sort -r); do
		if [ -x "$d/bin/go" ]; then
			PATH="$d/bin:$PATH"
			export PATH
			break
		fi
	done
fi
if command -v go >/dev/null 2>&1; then
	GOROOT=$(go env GOROOT)
	export GOROOT
	echo "go=$(command -v go)  GOROOT=$GOROOT  $(go version)"
else
	say "go が見つからない。rules_go が host SDK を見つけられずに落ちる"
	exit 1
fi

##### 2. 枝を取る #####
echo '##### 2. probe/plain-upstream を取る #####'
SRCDIR=$W/bazel
rm -rf "$SRCDIR"
git clone -q --depth 1 -b "$BRANCH" "$REPO" "$SRCDIR"
cd "$SRCDIR"
git log --oneline -1
[ -f ci/bsd-bootstrap.sh ] || { say "ci/bsd-bootstrap.sh が無い"; exit 1; }

##### 3. 踏み台を建てる #####
echo '##### 3. 踏み台の bazel を建てる #####'
export SRCDIR
# 作業場はあちらに選ばせる。bsd-bootstrap.sh は WORK_FORCED が無ければ空きの
# 一番多い場所を自分で選び (VM では /var/tmp が 183GB で、こちらが渡す
# /home より広かった)、建てた binary の path を BOOTSTRAP_OUT の file へ書く。
# 決め打ちで探すと、あちらが場所を変えた瞬間に「見つからない」になる。
export BOOTSTRAP_OUT=$W/bootstrap-bazel-path
rm -f "$BOOTSTRAP_OUT"
# ulimit は bootstrap でも要る。OpenBSD の既定の記述子上限では
# Too many open files で落ちる。
ulimit -n unlimited 2>/dev/null || ulimit -n 4096 2>/dev/null || true
ulimit -d unlimited 2>/dev/null || true

if sh ci/bsd-bootstrap.sh; then
	say "bootstrap OK"
else
	say "bootstrap 失敗"
	exit 1
fi

B=""
if [ -s "$BOOTSTRAP_OUT" ]; then
	B=$(cat "$BOOTSTRAP_OUT")
fi
if [ -z "$B" ] || [ ! -x "$B" ]; then
	say "踏み台の bazel が見つからない (BOOTSTRAP_OUT=$BOOTSTRAP_OUT の中身: ${B:-空})"
	exit 1
fi
echo "踏み台: $B"
"$B" --version

# set -e の下で `[ ... ] && { ...; }` を素で置くと、偽のときにその AND 列の
# 終了値が 1 になって script ごと終わる。if で書く。
if [ "$STAGE" = bootstrap ]; then
	say "段 bootstrap まで完了"
	exit 0
fi

##### 4. rules_cc の toolchain を測る #####
# bazel 本体は建てない。踏み台で小さな C++ を建てて、出来た binary を調べる。
# rules_cc #862 で c2qd さんが挙げた二つの回帰を見る。
#
#   #854  OpenBSD の ld.so は DF_ORIGIN が無いと $ORIGIN を展開しない。
#         cc_binary が linkstatic=False で cc_library を引くと RPATH に
#         $ORIGIN が入るので、展開されないと共有 library を読めずに死ぬ。
#   #857  driver が -lstdc++ を -lc++ -lc++abi -lpthread へ展開するが、
#         --as-needed で包むと libpthread が落ちる。
#
# **「走った」では判定できない。** libpthread が欠けていても OpenBSD は
# undefined symbol を stderr へ並べたうえで main を走らせ、標準出力は出る。
# NEEDED の一覧と stderr の中身で見る。
if [ "$STAGE" = rules-cc ]; then
	echo '##### 4. rules_cc の toolchain を測る #####'
	RC=$W/rules_cc
	rm -rf "$RC"
	git clone -q --depth 1 -b "${RC_BRANCH:-bsd-autoconf-verify}" \
		"${RC_REPO:-https://github.com/zakinko/rules_cc.git}" "$RC"
	(cd "$RC" && git log --oneline -1)

	T=$W/rctest
	rm -rf "$T"; mkdir -p "$T/lib"
	cat > "$T/MODULE.bazel" <<'M'
module(name = "rctest")
bazel_dep(name = "rules_cc", version = "0.2.22")
M
	cat > "$T/BUILD.bazel" <<'M'
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

# #854 の再現。linkstatic=False なので RPATH に $ORIGIN が入る。
cc_library(name = "func", srcs = ["lib/func.cpp"])

cc_binary(
    name = "main",
    srcs = ["main.cpp"],
    deps = [":func"],
    linkstatic = False,
)

# #857 の再現。libc++ と libc++abi が pthread を要る。
cc_binary(name = "hello", srcs = ["hello.cpp"])
M
	echo 'extern int func();
int main() { return func(); }' > "$T/main.cpp"
	echo 'int func() { return 0; }' > "$T/lib/func.cpp"
	echo '#include <iostream>
int main() { std::cout << "hello-from-rules-cc\n"; }' > "$T/hello.cpp"

	cd "$T"
	"$B" build --repo_contents_cache= --override_module=rules_cc="$RC" //... \
		|| { say "rules_cc の test workspace が建たない"; exit 1; }

	fail=0

	echo "--- NEEDED の一覧 (#857) ---"
	need=""
	for t in objdump readelf; do
		if command -v "$t" >/dev/null 2>&1; then need=$t; break; fi
	done
	case "$need" in
	objdump) objdump -p bazel-bin/hello | grep NEEDED || true ;;
	readelf) readelf -d bazel-bin/hello | grep NEEDED || true ;;
	*)       ldd bazel-bin/hello || true ;;
	esac
	if [ "$OS" = OpenBSD ]; then
		if { objdump -p bazel-bin/hello 2>/dev/null || readelf -d bazel-bin/hello 2>/dev/null; } \
		   | grep -q 'pthread'; then
			say "#857 OK: libpthread が NEEDED に居る"
		else
			say "#857 NG: libpthread が NEEDED に無い"
			fail=1
		fi
	fi

	echo "--- 走らせる (#857) ---"
	./bazel-bin/hello > "$T/hello.out" 2> "$T/hello.err" || true
	cat "$T/hello.out"; cat "$T/hello.err"
	if grep -q 'undefined symbol' "$T/hello.err"; then
		say "#857 NG: undefined symbol が出た"
		fail=1
	else
		say "#857 OK: undefined symbol は出ない"
	fi

	echo "--- \$ORIGIN (#854) ---"
	if ./bazel-bin/main > "$T/main.out" 2> "$T/main.err"; then
		say "#854 OK: \$ORIGIN 付きの binary が走る"
	else
		cat "$T/main.err"
		say "#854 NG: \$ORIGIN 付きの binary が走らない"
		fail=1
	fi

	if [ $fail -eq 0 ]; then
		say "段 rules-cc まで完了"
		exit 0
	fi
	say "rules-cc の検査が落ちた"
	exit 1
fi

##### 5. master を建てる #####
echo '##### 5. upstream master を建てる #####'
export B
export SRC=$W/mst
export PATCH859=$SRCDIR/ci/rules_cc_859.patch
# set -e の下で `[ ... ] && export ...` を素で置くと、file が無いときに
# その AND 列の終了値が 1 になって script ごと終わる。if で書く。
if [ -f "$SRCDIR/ci/rules_python_quote_args.patch" ]; then
	export PATCH_RULES_PYTHON=$SRCDIR/ci/rules_python_quote_args.patch
fi
# master-build.sh の既定に合わせて 2。VM は 4 CPU だが memory は 8GB で、
# bazel の JVM と C++ の compile が同時に伸びる。上げるなら、上げた run で
# memory が足りることを見てからにする。
export JOBS=${JOBS:-2}

if sh ci/master-build.sh; then
	say "master OK"
else
	say "master 失敗"
	exit 1
fi
