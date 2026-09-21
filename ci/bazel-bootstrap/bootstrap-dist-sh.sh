#!/bin/sh
# 手元にある dist archive を、$SH_BIN だけで bootstrap し、出来た bazel で煙試験
# まで通す。dist は make-master-dist.sh が枝から作った物 (OS に依らない)。
#
# 使い方: bootstrap-dist-sh.sh <dist.zip>
#   SH_BIN       compile.sh を起動する shell と genrule の shell (既定 /bin/sh)
#   LOG_BASH     1 なら /bin/bash を記録 wrapper に差し替えて、bootstrap の間に
#                誰が bash を呼んだかを数える (root か sudo が要る)
#   NO_VIS       1 なら --check_visibility=false。master の bazel が rules_python
#                1.7.0 を visibility で弾く (bash でも同じ) のを越えるため
#   EXTRA_PATCH  dist に当てる当て物 (Alpine の musl 用など)
#   JAVA_HOME    必須
set -eu

DIST=$1
# 同梱の当て物と script は cd する前に絶対 path で覚える。相対のままだと
# $WORK へ移ったあとで見つからない (Alpine で rules_java の当て物が見つからず落ちた)。
CI_DIR=$(cd "$(dirname "$0")" && pwd)
SH_BIN=${SH_BIN:-/bin/sh}
LOG_BASH=${LOG_BASH:-0}
NO_VIS=${NO_VIS:-0}
EXTRA_PATCH=${EXTRA_PATCH:-}
WORK=${WORK:-$PWD/dist-sh-work}
OS=$(uname -s)

echo "=== JDK / OS / sh"
"${JAVA_HOME:?JAVA_HOME が要る}/bin/javac" -version
uname -srm; "$SH_BIN" -c 'echo "sh は $0"'
[ -f "$DIST" ] || { echo "$DIST が無い"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK/dist"
( cd "$WORK/dist" && unzip -q "$DIST" )
cd "$WORK/dist"
for f in compile.sh scripts/bootstrap/compile.sh scripts/bootstrap/buildenv.sh scripts/bootstrap/bootstrap.sh; do
	head -1 "$f" | grep -q '^#!/bin/sh$' || { echo "$f の shebang が #!/bin/sh でない (dist に枝の変更が入っていない)"; exit 1; }
done
if [ -n "$EXTRA_PATCH" ]; then
	echo "=== 当て物を当てる ($EXTRA_PATCH)"
	patch -p1 -f -i "$EXTRA_PATCH" </dev/null
fi

# BSD では rules_python が配る CPython が無く、MODULE.bazel の pip.parse が
# 評価の時点で interpreter を要って module extension ごと落ちる
# (hub_builder.bzl の Traceback)。pip の塊を使うのは bazel_nojdk の graph の
# 外だけなので、踏み台を建てる間は落とす。zakinko/bazel の
# probe/plain-upstream の ci/master-bootstrap.sh と同じ手当て。
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|OpenBSD|NetBSD|DragonFly)
	echo "=== pip の塊を落とす (BSD)"
	python3 "$CI_DIR/drop_pip_dev_deps.py" .
	if grep -rq bazel_pip_dev_deps MODULE.bazel third_party/py 2>/dev/null; then
		echo "pip の塊が残っている"; exit 1
	fi
	# master が固定する protobuf 36 は、_POSIX_C_SOURCE を define するせいで
	# BSD の libc++ の <locale> が isascii を見失って翻訳できない
	# (protocolbuffers/protobuf#29694 で直しを出してある)。bazel は protobuf に
	# 自前の当て物 (third_party/protobuf.patch) を差しているので、その末尾に
	# 同じ 6 行を足す。sh 化とは無関係で、bash で建てても同じ所で落ちる。
	echo "=== protobuf #29694 を third_party/protobuf.patch に足す (BSD)"
	cat "$CI_DIR/protobuf-29694.patch" >> third_party/protobuf.patch ;;
esac

# OS ごとの手当て。どれも sh 化とは無関係で、素の dist を bash で建てるときにも要る物。
EXTRA_BAZEL_ARGS="${EXTRA_BAZEL_ARGS:-} --shell_executable=$SH_BIN"
case "$OS" in
Darwin)
	# clang の module map で grpc が layering_check に落ちる
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --features=-layering_check" ;;
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|OpenBSD|NetBSD|DragonFly)
	# libm は別 library。FreeBSD の devel/bazel9 も同じ
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --host_linkopt=-lm --linkopt=-lm"
	ulimit -n unlimited 2>/dev/null || ulimit -n 4096 2>/dev/null || true
	ulimit -d unlimited 2>/dev/null || true ;;
esac
case "$OS" in
MINGW*|MSYS*|CYGWIN*)
	# exec 構成の genrule (fastutil の zip) に client の PATH を届ける。
	# 9.3.0 の Windows の job と同じ。
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --host_action_env=PATH" ;;
esac
if [ "$OS" = OpenBSD ]; then
	# C++ の object を C の driver で link するので runtime を明示する
	for l in -lc++ -lc++abi -lpthread; do
		EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --host_linkopt=$l --linkopt=$l"
	done
fi
if [ "$NO_VIS" = 1 ]; then
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --check_visibility=false"
fi
export EXTRA_BAZEL_ARGS
echo "EXTRA_BAZEL_ARGS=$EXTRA_BAZEL_ARGS"

BASHLOG=""
if [ "$LOG_BASH" = 1 ]; then
	BASHLOG=$WORK/bash-calls.log; : > "$BASHLOG"
	BASH_REAL=$(command -v bash || true)
	if [ -z "$BASH_REAL" ]; then
		echo "bash が無い箱なので記録は要らない"
	elif [ /bin/sh -ef "$BASH_REAL" ] || [ "$(readlink -f /bin/sh 2>/dev/null)" = "$(readlink -f "$BASH_REAL" 2>/dev/null)" ]; then
		# Fedora や Arch は /bin/sh が bash への symlink。bash を動かすと sh 自身が
		# 消えて何も動かなくなる (run 35611323359 で "sh: command not found")。
		# この箱では sh で走らせることと bash で走らせることが同じ物なので、
		# 数える意味も無い。
		echo "/bin/sh が bash そのもの ($BASH_REAL) なので記録 wrapper は張らない"
		BASHLOG=""
	else
		SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo
		$SUDO mv "$BASH_REAL" "$BASH_REAL.real"
		$SUDO sh -c "cat > '$BASH_REAL'" <<WRAP
#!/bin/sh
printf 'ppid=%s cwd=%s args=%s\\n' "\$PPID" "\$PWD" "\$*" >> "$BASHLOG"
exec "$BASH_REAL.real" "\$@"
WRAP
		$SUDO chmod 755 "$BASH_REAL"
		echo "$BASH_REAL を記録 wrapper にした"
	fi
fi

echo "=== bootstrap を $SH_BIN で"
"$SH_BIN" ./compile.sh > compile.log 2>&1 || true
BZ=output/bazel
if [ -x output/bazel.exe ]; then BZ=output/bazel.exe; fi
if [ -x "$BZ" ] && "$BZ" version 2>/dev/null | grep -q '^Build label:'; then
	"$BZ" version | grep 'Build label'
	echo "RESULT master-sh $OS $SH_BIN OK: 枝の dist を sh だけで bootstrap できた"
else
	echo "RESULT master-sh $OS $SH_BIN NG"
	grep -n 'error\|ERROR\|not found\|Syntax\|syntax\|Bad substitution\|Bad fd\|unexpected' compile.log | tail -20
	tail -40 compile.log
	exit 1
fi

if [ -n "$BASHLOG" ]; then
	n=$(wc -l < "$BASHLOG" | tr -d ' ')
	echo "=== bootstrap の間に bash を呼んだ回数: $n"
	sed 's/^ppid=[0-9]* cwd=[^ ]* args=//' "$BASHLOG" | awk '{print $1, $2}' | sort | uniq -c | sort -rn | head -20
	echo "RESULT bash-calls $OS $n"
fi

echo "=== 煙試験"
case "$OS" in
MINGW*|MSYS*|CYGWIN*)
	# MSYS は //p:gen を /p:gen に path 変換して "invalid package name" になる。
	# label を変換の対象から外す。
	# '*' だと --repository_cache= の path 変換まで止まって bazel が動かない。
	# label だけを外す。
	MSYS2_ARG_CONV_EXCL='//'; export MSYS2_ARG_CONV_EXCL ;;
esac
mkdir -p "$WORK/smoke/p"; cd "$WORK/smoke"
RJ=$(grep -o 'name = "rules_java", version = "[^"]*"' "$WORK/dist/MODULE.bazel" | sed 's/.*version = "//; s/"//')
RC=$(grep -o 'name = "rules_cc", version = "[^"]*"' "$WORK/dist/MODULE.bazel" | sed 's/.*version = "//; s/"//')
printf 'bazel_dep(name = "rules_cc", version = "%s")\nbazel_dep(name = "rules_java", version = "%s")\n' "$RC" "$RJ" > MODULE.bazel
# rules_java の既定 toolchain は java_runtime に remotejdk_25 を決め打ちし、
# ijar / singlejar / turbine は linux_x86_64 なら glibc 向けの prebuilt を選ぶ。
# 遠隔 JDK の無い BSD と、prebuilt が動かない musl では、rules_java に当て物を
# 差して既定 toolchain を local の JDK と source 建ての道具に向ける。glibc の
# Linux と macOS と Windows は素の rules_java のまま (そこは素で通る)。
RJ_PATCH=""
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|OpenBSD|NetBSD|DragonFly) RJ_PATCH=1 ;;
Linux) if [ -e /lib/ld-musl-x86_64.so.1 ]; then RJ_PATCH=1; fi ;;
esac
if [ -n "$RJ_PATCH" ]; then
	P="$CI_DIR/rules_java-$RJ-local.patch"
	[ -f "$P" ] || { echo "rules_java $RJ 向けの当て物 ($P) が無い"; exit 1; }
	cp "$P" rules_java-local.patch
	printf 'single_version_override(\n    module_name = "rules_java",\n    version = "%s",\n    patch_strip = 1,\n    patches = ["//:rules_java-local.patch"],\n)\n' "$RJ" >> MODULE.bazel
	: > BUILD
	echo "rules_java $RJ に当て物を差した"
fi
cat > p/BUILD <<'B'
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_java//java:java_binary.bzl", "java_binary")
genrule(name = "gen", outs = ["gen.txt"], cmd = "echo genrule-ok > $@")
cc_binary(name = "hello_cc", srcs = ["hello.cc"])
java_binary(name = "hello_java", srcs = ["Hello.java"], main_class = "Hello")
B
printf '#include <cstdio>\nint main() { std::printf("cc-ok\\n"); return 0; }\n' > p/hello.cc
printf 'public class Hello { public static void main(String[] a) { System.out.println("java-ok"); } }\n' > p/Hello.java
# rules_java の遠隔 JDK と prebuilt (ijar, singlejar) は Linux glibc / macOS /
# Windows の分しか配られていない。BSD と musl では java_binary の煙試験は
# rules_java の platform 対応を測ることになり、この枝の話ではない。そこでは
# local の JDK を指して試し、落ちても報告に留めて job は落とさない。
JAVA_ARGS=""
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|OpenBSD|NetBSD|DragonFly) JAVA_ARGS="--java_runtime_version=local_jdk --tool_java_runtime_version=local_jdk" ;;
Linux) if [ -e /lib/ld-musl-x86_64.so.1 ]; then JAVA_ARGS="--java_runtime_version=local_jdk --tool_java_runtime_version=local_jdk"; fi ;;
esac
rc=0
for t in gen hello_cc hello_java; do
	if [ "$t" = gen ]; then act=build; else act=run; fi
	extra=""; if [ "$t" = hello_java ]; then extra=$JAVA_ARGS; fi
	if "$WORK/dist/$BZ" $act --repository_cache="$WORK/dist/derived/repository_cache" ${EXTRA_BAZEL_ARGS:-} $extra "//p:$t" > "$WORK/smoke-$t.log" 2>&1; then
		echo "SMOKE //p:$t OK"
	else
		echo "SMOKE NG //p:$t"; tail -20 "$WORK/smoke-$t.log"; rc=1
	fi
done
if [ "$rc" = 0 ]; then echo "RESULT smoke $OS OK: genrule と cc と java が走った"; fi
exit $rc
