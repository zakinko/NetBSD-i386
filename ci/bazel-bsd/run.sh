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
#	stock      指定した release の dist を、枝の変更を一切被せずに建てる。
#	           「今の上流の release がこの BSD でそのまま建つか」を測る段。
#	           DIST_VER で版を選ぶ (既定 9.3.0rc2)
#
# 使い方:
#	sh ci/bazel-bsd/run.sh [bootstrap|stock|posix-sh|rules-cc|master]
set -eu

STAGE=${1:-bootstrap}
BRANCH=${BRANCH:-probe/plain-upstream}
REPO=${REPO:-https://github.com/zakinko/bazel.git}

# stock の段は素の dist をそのまま建てる。枝の当て物を被せると、上流の
# release が素で建つかという問いに答えられなくなる。
if [ "$STAGE" = stock ]; then
	PLAIN=1
	export PLAIN
	DIST_VER=${DIST_VER:-9.3.0rc2}
	# STOCK_PATCH_NAME が来たら、ci/bazel-bootstrap/ のその当て物を素の木へ
	# 一枚だけ当てる。「素で落ちる」と「その一行を直せば建つ」は別の主張で、
	# 後者は当てた run を指せないと言えない。
	if [ -n "${STOCK_PATCH_NAME:-}" ]; then
		STOCK_PATCH=$GITHUB_WORKSPACE/ci/bazel-bootstrap/$STOCK_PATCH_NAME
		[ -f "$STOCK_PATCH" ] || { say "$STOCK_PATCH が無い"; exit 1; }
		export STOCK_PATCH
		echo "### 素の木へ当てる: $STOCK_PATCH_NAME"
	fi
fi
if [ -n "${DIST_VER:-}" ]; then
	export DIST_VER
	echo "### dist の版: $DIST_VER"
fi

# posix-sh の段では bash を入れない。BSD は base に bash を持たないので、
# 入れなければ本当に存在しない箱になる。そこで bootstrap script の POSIX sh
# 版が /bin/sh だけで建つかを測るのがこの段の趣旨である。
if [ "$STAGE" = posix-sh ]; then
	BASH_PKG=""
else
	BASH_PKG="bash"
fi

say() { echo "RESULT $*"; }

# 生成された local_config_cc/BUILD から、一つの attribute の値を丸ごと出す。
#
#	tc_field <BUILD> link_flags
#
# 一覧は複数行に折れている (get_starlark_list が '",\n    "' で繋ぐ) ので、
# 行単位では拾えない。key の行から ] の在る行までを出す。key は行頭に錨を
# 打つ。打たないと link_flags が opt_link_flags と coverage_link_flags にも
# 当たり、短い方だけが出て長い本命が落ちる。
tc_field() {
	awk -v k="$2" '
		!inb && $0 ~ "^[ \t]*" k " = \\[" { inb = 1; print; if (/\]/) exit; next }
		inb { print; if (/\]/) exit }
	' "$1"
}

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
	for p in git-base $BASH_PKG python313 unzip zip go; do
		pkg_add -U "$p" || say "pkg_add $p が入らなかった"
	done
	# 21 を採る。JDK 23 から annotation processing が既定で走らないので、
	# bazel 9.2.0 の bootstrap は 25 では建たない (上の JAVA_HOME の註)。
	pkg_add -U openjdk21 || say "JDK の package が入らなかった"
	;;
FreeBSD|GhostBSD)
	env ASSUME_ALWAYS_YES=yes pkg install -y git $BASH_PKG openjdk21 python3 unzip zip go || true
	;;
DragonFly)
	pkg install -y git $BASH_PKG openjdk21 python3 unzip zip go || true
	;;
OpenBSD)
	export PKG_PATH="https://cdn.openbsd.org/pub/OpenBSD/$(uname -r)/packages/$(uname -m)/"
	for p in git $BASH_PKG zip go; do
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

# master の段だけが要るもの。
#
# master は git の木なので compile.sh が PROTOC を要求する。手当ての側は
# 「protoc は package に在る」前提で書いてあり、無いと
#
#	protoc が無い。package を入れる
#
# と言って止まる。dist archive から建てる bootstrap の段には要らないので、
# 数分を毎回払わないよう段で分ける。
#
#	https://github.com/zakinko/NetBSD-i386/actions/runs/35015325674
#
# protoc が 30 より古いと master-bootstrap.sh が protobuf を source から
# 組み直す。そこでだけ cmake と ninja が要る。DragonFly の dports は 29.3 が
# 最新なので、そちらには初めから入れておく。
if [ "$STAGE" = master ]; then
	echo '--- master の段の依存'
	case "$OS" in
	NetBSD)
		for p in protobuf pkg-config; do
			pkg_add -U "$p" || say "pkg_add $p が入らなかった"
		done
		;;
	FreeBSD|GhostBSD)
		# ports の protobuf も 29.6 で 30 に届かない (run 35129102405 の
		# freebsd)。source から組む側の cmake と ninja も入れる。
		env ASSUME_ALWAYS_YES=yes pkg install -y protobuf pkgconf cmake ninja || true
		;;
	DragonFly)
		# dports の protobuf 29.3 は abseil 2501 の .so を要るが、pkg install は
		# 箱に元から在る古い abseil で依存が満たされたと見て上げない。
		#
		#	Shared object "libabsl_die_if_null.so.2501.0.0" not found,
		#	  required by "protoc"
		#	https://github.com/zakinko/NetBSD-i386/actions/runs/35129102405
		#
		# abseil を名指しで上げる。
		pkg install -y protobuf pkgconf cmake ninja || true
		pkg upgrade -y abseil || pkg install -y abseil || true
		;;
	OpenBSD)
		# pkg-config は base に在る。
		pkg_add -I protobuf || say "pkg_add protobuf が入らなかった"
		;;
	esac
fi

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
# master 段は master-bootstrap.sh が compile.sh から直接起こすので踏み台が
# 要らない。ここを飛ばすと三十分浮く。
if [ "$STAGE" = master ]; then
	echo '##### 3. 踏み台は master 段では要らないので飛ばす #####'
else

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

# posix-sh の段では、bootstrap script を POSIX sh 版に差し替えて /bin/sh だけで
# 建てる。当て物は NetBSD-i386 の側に在るので、VM から見える path を渡す。
if [ "$STAGE" = posix-sh ]; then
	P=$GITHUB_WORKSPACE/ci/bazel-bootstrap/posix-sh.patch
	[ -f "$P" ] || { say "posix-sh.patch が無い ($P)"; exit 1; }
	POSIX_SH_PATCH=$P; export POSIX_SH_PATCH
	BAZEL_SH=/bin/sh; export BAZEL_SH
	echo "bash: $(command -v bash 2>/dev/null || echo '無い)')"
	echo "posix-sh の段: $POSIX_SH_PATCH を当てて $BAZEL_SH で建てる"
fi

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
if [ "$STAGE" = bootstrap ] || [ "$STAGE" = stock ]; then
	say "段 $STAGE まで完了${DIST_VER:+ (dist $DIST_VER)}"
	exit 0
fi

if [ "$STAGE" = posix-sh ]; then
	# bash の package は入れていないが、他の package が依存で引き込むことが
	# ある (NetBSD は go か python3 が /usr/pkg/bin/bash を連れてきた)。
	# 入っている箱で「bash 無しで完走」と言うと嘘になるので、実態を見て
	# 主張を分ける。
	if command -v bash >/dev/null 2>&1; then
		say "posix-sh $OS OK: script は /bin/sh で動いた (ただし bash が $(command -v bash) に在る箱。build 全体が bash を使わないことの証明にはならない)"
	else
		say "posix-sh $OS OK: bash が無い箱で /bin/sh だけで bootstrap 完走"
	fi
	exit 0
fi

fi   # STAGE = master のときに飛ばした分の閉じ

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
	# echo に \n を渡さない。OpenBSD の sh (ksh) の echo は backslash を
	# 解釈するので、C++ の文字列の中に生の改行が入り
	#
	#	hello.cpp:2:27: warning: missing terminating '"' character
	#	hello.cpp:2:27: error: expected expression
	#
	# で compile が落ちる。#857 の回帰検査はその手前で止まるので、link を
	# 一度も測らないまま「落ちた」になる。
	#
	#	https://github.com/zakinko/NetBSD-i386/actions/runs/35015123723
	cat > "$T/hello.cpp" <<'M'
#include <iostream>
int main() { std::cout << "hello-from-rules-cc" << std::endl; }
M

	cd "$T"
	"$B" build --repo_contents_cache= --override_module=rules_cc="$RC" //... \
		|| { say "rules_cc の test workspace が建たない"; exit 1; }

	fail=0

	# 生成された toolchain そのものを見る。#862 の review で
	#
	#	should we be worried that this logic would select gcc on bsd if
	#	they had that installed alongside the default?
	#
	# と訊かれている所で、手元で一度測って終わりにすると主張だけが残る。
	# BSD の base には cc と gcc が同じものとして両方在るか、gcc が無いので、
	# ここで /usr/bin/cc 以外を掴んでいたら ports や pkgsrc のものを拾って
	# いる。出して、かつ落とす。
	#
	# 見るのは BUILD であって cc_toolchain_config.bzl ではない。後者は rule の
	# 実装で、値の所は ctx.attr.compiler のような参照でしかない。そちらを
	# grep して「driver の path を読み取れない」を出した。
	#
	#	https://github.com/zakinko/NetBSD-i386/actions/runs/35061461816
	#
	# 生成された値は BUILD の cc_toolchain_config(...) の中に在る。
	#
	# その前に、箱の compiler そのものを出しておく。#862 の返信に書いた
	# 「NetBSD と DragonFly は cc と gcc が同じ物」「DragonFly に
	# /usr/bin/clang も /usr/bin/dwp も無く、-lc++ は繋がらず -lstdc++ は
	# 繋がる」は、消してしまった Vultr の箱で手で測った値だった。ここで
	# 毎回出せば run の URL で指せる。link の probe は source ではなく
	# object を渡す。source を渡すと driver が runtime を足して何でも通る。
	echo "--- 箱の compiler ---"
	for t in cc gcc clang c++ g++ clang++; do
		p=$(command -v "$t" 2>/dev/null || true)
		if [ -n "$p" ]; then
			printf '  %-8s %s  %s\n' "$t" "$p" "$("$p" --version 2>/dev/null | head -1)"
		else
			printf '  %-8s (無し)\n' "$t"
		fi
	done
	for f in /usr/bin/clang /usr/bin/dwp; do
		if [ -e "$f" ]; then echo "  $f  在る"; else echo "  $f  無い"; fi
	done
	echo "  -- link probe (object を渡す)"
	P=$W/linkprobe
	rm -rf "$P"; mkdir -p "$P"
	printf 'int main(void) { return 0; }\n' > "$P/p.c"
	if cc -c -o "$P/p.o" "$P/p.c" 2>"$P/cc.err"; then
		for lib in -lc++ -lstdc++ -lm -lpthread; do
			if cc -o "$P/p" "$P/p.o" "$lib" 2>"$P/l.err"; then
				printf '  cc p.o %-10s 繋がる\n' "$lib"
			else
				printf '  cc p.o %-10s 落ちる: %s\n' "$lib" "$(head -1 "$P/l.err" | cut -c1-80)"
			fi
		done
	else
		echo "  cc -c が落ちた: $(head -1 "$P/cc.err")"
	fi

	echo "--- 生成された toolchain (#862) ---"
	OB=$("$B" info output_base 2>/dev/null || true)
	LCC=""
	if [ -n "$OB" ]; then
		LCC=$(find "$OB/external" -maxdepth 1 -name '*local_config_cc' -type d 2>/dev/null | head -1)
	fi
	if [ -z "$LCC" ] || [ ! -f "$LCC/BUILD" ]; then
		say "#862 測れない: local_config_cc/BUILD が見つからない (output_base=$OB)"
		fail=1
	else
		grep -E '^ *(toolchain_identifier|compiler|target_libc|host_system_name|cpu) = "' \
			"$LCC/BUILD" | sed 's/^ */  /'
		echo "  -- tool_paths"
		grep -o '"gcc": *"[^"]*"' "$LCC/BUILD" | sed 's/^/    /'
		# 一覧は必ず複数行に折れている。lib_cc_configure.bzl の
		# get_starlark_list が '",\n    "' で繋ぐためで、行単位の grep -o では
		# 一項目しかない短い key しか拾えない。実際 link_flags を指したつもりで
		# opt_link_flags と coverage_link_flags だけが出ていた。
		#
		#	https://github.com/zakinko/NetBSD-i386/actions/runs/35067051116
		#
		# key の行から始めて、] の在る行まで出す。key は行頭に錨を打つ。
		# そうしないと link_flags が opt_link_flags にも当たる。
		for k in cxx_builtin_include_directories link_flags link_libs; do
			echo "  -- $k"
			tc_field "$LCC/BUILD" "$k" | sed 's/^/    /' | head -14
		done

		drv=$(sed -n 's/.*"gcc": *"\([^"]*\)".*/\1/p' "$LCC/BUILD" | head -1)
		case "$drv" in
		*/cc)  say "#862 OK: C の driver は $drv" ;;
		"")    say "#862 測れない: driver の path を読み取れない"; fail=1 ;;
		*)     say "#862 NG: cc ではなく $drv を掴んでいる"; fail=1 ;;
		esac

		# #854 は OpenBSD の話なので、そこだけ設定の側でも断定する。
		# 他の BSD は ld が -z origin を取るとは限らないので出すだけ。
		#
		# file 全体を grep してはいけない。「link_flags に在る」と言いながら
		# 別の key に在っても通ってしまう。link_flags の中だけを見る。
		if [ "$OS" = OpenBSD ]; then
			if tc_field "$LCC/BUILD" link_flags | grep -q 'z,origin'; then
				say "#854 OK: link_flags に -z origin が在る"
			else
				say "#854 NG: link_flags に -z origin が無い"
				fail=1
			fi
		fi
	fi

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

	# 走ることだけを見てはいけない。RPATH に $ORIGIN が入っていなければ、
	# あるいは共有 library を要求していなければ、当て物を外しても走ってしまい、
	# 検査が何も測らないまま緑になる。測る物が在ることを先に確かめる。
	echo "--- \$ORIGIN (#854) ---"
	dyn=$({ objdump -p bazel-bin/main 2>/dev/null || readelf -d bazel-bin/main 2>/dev/null; })
	echo "$dyn" | grep -E 'RPATH|RUNPATH|NEEDED' || true
	# $ORIGIN が RPATH に入っていれば、共有 library をそこから引く形になって
	# いる。入っていなければ静的に繋がったということで、DF_ORIGIN の有無を
	# 測れる状態ではない。NEEDED の名前は箱ごとに違いうるので断定せず、
	# 記録に残すだけにする。
	if ! echo "$dyn" | grep -qE '(RPATH|RUNPATH).*\$ORIGIN'; then
		say "#854 測れない: RPATH に \$ORIGIN が無い (linkstatic=False が効いていない)"
		fail=1
	elif ./bazel-bin/main > "$T/main.out" 2> "$T/main.err"; then
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
# 呼ぶのは master-bootstrap.sh であって master-build.sh ではない。
#
# 二つは別の経路である。master-build.sh は踏み台の bazel で master を建てる
# 形で、remotejdk_25 の書き換えは持っているが drop_pip_dev_deps.py を呼ばない。
# それで
#
#	Unable to find interpreter for pip hub 'bazel_pip_dev_deps'
#	  for python_version=3.11
#
# で落ちた (最初にこちらを呼んで踏んだ)。master-bootstrap.sh の方が
# 「踏み台なしで master を起こす」本体で、三つの手当てを全部持っている。
# protoc と gRPC の Java plugin も自分で用意する。
#
#	https://github.com/zakinko/NetBSD-i386/actions/runs/35008969162
echo '##### 5. upstream master を建てる #####'
export W
export SRC=$W/mst
export BZ=$SRCDIR
export JOBS=${JOBS:-2}

if sh ci/master-bootstrap.sh; then
	say "master OK"
else
	say "master 失敗"
	exit 1
fi
