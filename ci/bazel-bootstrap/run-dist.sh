#!/bin/sh
# bazel の release dist archive を JAVA_HOME の JDK で bootstrap する。
#
# release-9.3.0 へ出す当て物 (scripts/bootstrap の -proc:full 二箇所) が
# Linux と macOS でも通ることを CI で見るためのもの。dist archive は自己完結
# なので protoc も network も要らず、compile.sh が両方の javac の呼び出しを
# 通る (踏み台の javac と、その踏み台が java_rules_skylark.bzl の genrule で
# 呼ぶ JDK の javac)。
#
# 使い方: run-dist.sh <当て物>
#   当て物は proc-full.patch (両方) / proc-full-compile-only.patch /
#   proc-full-bootstrap-only.patch のどれか。半分ずつ当てると、どちらの半分が
#   どの箱で効いているかが分かれる
#   DIST_VER   既定 9.3.0rc1。<ver> で releases/download/<ver>/bazel-<ver>-dist.zip
#   MODE       patched (既定): 当てて建て、bazel が出来て version を答えるか
#              control        : 当てずに建て、bazel が出来ないことを確かめる
#                               (JDK 23 以降でのみ意味がある)
#   CONTROL_EXPECT
#              nobuild (既定): control で bazel が出来たら失敗にする
#              either        : どちらでも失敗にせず、どちらだったかを報告する。
#                              JDK を 21 から順に掃いて「どの版から落ちるか」を
#                              測るときはこちら。21 や 22 では出来るのが正しい
#   SMOKE      1 なら、建った bazel で小さな workspace を建てて走らせる。
#              「bazel が出来た」と「その bazel が働く」は別の主張なので分ける
set -eu

PATCH=$1
DIST_VER=${DIST_VER:-9.3.0rc1}
MODE=${MODE:-patched}
CONTROL_EXPECT=${CONTROL_EXPECT:-nobuild}
SMOKE=${SMOKE:-0}
WORK=${WORK:-$PWD/bootstrap-work}
URL="https://github.com/bazelbuild/bazel/releases/download/${DIST_VER}/bazel-${DIST_VER}-dist.zip"

echo "=== JDK / OS"
"${JAVA_HOME:?JAVA_HOME を設定してください}/bin/javac" -version
JDK_LABEL=$("${JAVA_HOME}/bin/javac" -version 2>&1 | sed 's/javac //')
uname -sm

# macOS の clang は module map を持つので cc_configure が layering_check を
# 立て、grpc がその検査に通らない (thread_count.cc が module を export して
# いないと言って落ちる)。当て物とは無関係の C++ の問題で、master-bootstrap.sh
# が DragonFly に対してするのと同じく、踏み台を建てる間だけ切る。
case "$(uname -s)" in
Darwin) EXTRA_BAZEL_ARGS="--features=-layering_check"; export EXTRA_BAZEL_ARGS ;;
# third_party の fastutil / netty の genrule は zip / unzip を呼び、そのうち
# fastutil は [for tool] = exec 構成で走る。repo 直下 compile.sh は
# --action_env=PATH (target 構成) しか渡さないので、exec 構成の action には
# client の PATH が届かず、choco で入れた zip が見つからない (Exit 127)。
# exec 構成にも PATH を通す。
MINGW*|MSYS*|CYGWIN*) EXTRA_BAZEL_ARGS="--host_action_env=PATH"; export EXTRA_BAZEL_ARGS ;;
esac

rm -rf "$WORK"
mkdir -p "$WORK/src"
echo "=== $URL を取る"
curl -fsSL -o "$WORK/dist.zip" "$URL"
# Windows の Git Bash には unzip が無いことがあるので、7z か python へ落とす。
( cd "$WORK/src" && { unzip -q ../dist.zip \
	|| 7z x -y ../dist.zip >/dev/null \
	|| python -c "import zipfile;zipfile.ZipFile('../dist.zip').extractall()"; } )
cd "$WORK/src"
srcdir=$PWD

# compile.sh は一段目の javac が 178 errors で失敗しても exit 0 を返す
# (run が javac の失敗を伝えない)。だから成否は compile.sh の返り値ではなく、
# bazel が出来て version を答えるかで見る。Windows では output/bazel.exe。
bazel_bin() {
	if [ -x output/bazel ]; then echo output/bazel
	elif [ -x output/bazel.exe ]; then echo output/bazel.exe
	fi
}
built() {
	bz=$(bazel_bin)
	[ -n "$bz" ] && "$bz" version 2>/dev/null | grep -q '^Build label:'
}

# 「bazel が出来た」は「その bazel が働く」ではない。建った bazel で小さな
# workspace を建てて走らせ、答えが返るところまで見る。
#
# dist archive に examples/ は入っていない (rc2 の中身を数えて確かめた) ので、
# ここで作る。版は dist 自身の MODULE.bazel と同じ物にして、bootstrap が
# 埋めた derived/repository_cache から解決させる。
#
# cc と java の両方を通すのは落ちる筋が別だから。cc は cc_configure が箱の
# compiler を見つけられるか、java は toolchain と annotation processor。
smoke_test() {
	bz=$srcdir/$(cd "$srcdir" && bazel_bin)
	cache="$srcdir/derived/repository_cache"
	echo "=== 煙試験: 建った bazel で小さな workspace を建てて走らせる"
	rm -rf "$WORK/smoke"
	mkdir -p "$WORK/smoke/p"
	cat > "$WORK/smoke/MODULE.bazel" <<'EOF'
bazel_dep(name = "rules_cc", version = "0.2.17")
bazel_dep(name = "rules_java", version = "9.1.0")
EOF
	cat > "$WORK/smoke/p/BUILD" <<'EOF'
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_java//java:java_binary.bzl", "java_binary")
load("@rules_java//toolchains:default_java_toolchain.bzl", "NONPREBUILT_TOOLCHAIN_CONFIGURATION", "default_java_toolchain")

# rules_java は linux_x86_64 なら無条件に glibc 向けの prebuilt (ijar, singlejar,
# turbine) を選び、musl を見分けない。Alpine ではそれが execvp で ENOENT に
# なるので、source から建てる構成の toolchain を自分で定義して登録する。
# SMOKE_NONPREBUILT=1 のときだけ --extra_toolchains で指す。
default_java_toolchain(
    name = "nonprebuilt",
    configuration = NONPREBUILT_TOOLCHAIN_CONFIGURATION,
    java_runtime = "@rules_java//toolchains:local_jdk",
    source_version = "21",
    target_version = "21",
)

genrule(
    name = "gen",
    outs = ["gen.txt"],
    cmd = "echo genrule-ok > $@",
)

cc_binary(
    name = "hello_cc",
    srcs = ["hello.cc"],
)

java_binary(
    name = "hello_java",
    srcs = ["Hello.java"],
    main_class = "Hello",
)
EOF
	cat > "$WORK/smoke/p/hello.cc" <<'EOF'
#include <cstdio>
int main() { std::printf("cc-ok\n"); return 0; }
EOF
	cat > "$WORK/smoke/p/Hello.java" <<'EOF'
public class Hello {
  public static void main(String[] a) { System.out.println("java-ok"); }
}
EOF
	SMOKE_ARGS=""
	if [ "${SMOKE_NONPREBUILT:-0}" = 1 ]; then
		SMOKE_ARGS="--extra_toolchains=//p:nonprebuilt_definition"
	fi
	rc=0
	for t in gen hello_cc hello_java; do
		echo "--- //p:$t"
		if [ "$t" = gen ]; then
			act="build"
		else
			act="run"
		fi
		if ( cd "$WORK/smoke" && "$bz" $act --repository_cache="$cache" \
			--verbose_failures ${EXTRA_BAZEL_ARGS:-} $SMOKE_ARGS "//p:$t" ) \
			> "$WORK/smoke-$t.log" 2>&1
		then
			tail -2 "$WORK/smoke-$t.log"
			echo "SMOKE //p:$t OK"
		else
			echo "SMOKE NG //p:$t"
			tail -30 "$WORK/smoke-$t.log"
			rc=1
		fi
	done
	if [ "$rc" = 0 ]; then
		echo "RESULT smoke $(uname -s) JDK$JDK_LABEL OK: genrule と cc と java が走った"
	else
		echo "RESULT smoke $(uname -s) JDK$JDK_LABEL NG"
	fi
	return $rc
}

if [ "$MODE" = patched ]; then
	echo "=== 当て物を当てる ($PATCH)"
	patch -p1 -f -i "$PATCH" </dev/null
	# 当て物は三通りある (両方 / compile.sh だけ / bootstrap.sh だけ)。
	# 当て物が触ると言っている file だけを検査する。触らない側まで数えると
	# 「入っていない」で落ちるが、それは入っていないのが正しい。
	if grep -q 'b/scripts/bootstrap/compile.sh' "$PATCH"; then
		grep -q -- '-proc:full' scripts/bootstrap/compile.sh \
			|| { echo "compile.sh に -proc:full が入っていない"; exit 1; }
	fi
	if grep -q 'b/scripts/bootstrap/bootstrap.sh' "$PATCH"; then
		n=$(grep -c 'javacopt=-proc:full' scripts/bootstrap/bootstrap.sh)
		[ "$n" -eq 2 ] || { echo "bootstrap.sh の -proc:full が $n 行 (2 のはず)"; exit 1; }
	fi

	echo "=== bootstrap (patched)"
	env bash ./compile.sh > compile.log 2>&1 || true
	if built; then
		"$(bazel_bin)" version | grep -i 'build label'
		echo "RESULT patched $(uname -s) JDK$JDK_LABEL OK ($(basename "$PATCH"))"
		if [ "$SMOKE" = 1 ]; then
			smoke_test
		fi
	else
		echo "当て物ありでも bazel が出来なかった"
		echo "--- command not found / Exit の類"
		grep -n -i 'command not found\|not found\|No such file\|Exit 12[0-9]\|cannot execute' compile.log | tail -20
		echo "--- error 行"
		grep -n 'error:\|errors$\|ERROR' compile.log | tail -20
		echo "--- compile.log の末尾 60 行"
		tail -60 compile.log
		exit 1
	fi
else
	echo "=== bootstrap (control: 素のまま。JDK 23 以降では bazel が出来ないはず)"
	env bash ./compile.sh > compile.log 2>&1 || true
	if built; then
		echo "RESULT control JDK$JDK_LABEL BUILT: 素のままでも働く bazel が出来た"
		"$(bazel_bin)" version | grep -i 'build label'
		if [ "$CONTROL_EXPECT" = either ]; then
			exit 0
		fi
		echo "この JDK では当て物が要らない"
		exit 1
	fi
	echo "--- bazel が出来なかった。理由を確かめる"
	if grep -q 'AutoOneOf_DependencyError' compile.log; then
		echo "RESULT control JDK$JDK_LABEL FAILED-stage1: compile.sh の javac が AutoOneOf が無いと言って落ちた"
	elif grep -q 'AutoValue_JarOwner' compile.log; then
		echo "RESULT control JDK$JDK_LABEL FAILED-stage2: genrule の javac が AutoValue が無いと言って落ちた"
	else
		echo "bazel は出来なかったが、想定した annotation processor のエラーが log に無い"
		grep -n 'error:' compile.log | head -10
		exit 1
	fi
fi
