#!/bin/sh
# bazel の release dist archive を JAVA_HOME の JDK で bootstrap する。
#
# release-9.3.0 へ出す当て物 (scripts/bootstrap の -proc:full 二箇所) が
# Linux と macOS でも通ることを CI で見るためのもの。dist archive は自己完結
# なので protoc も network も要らず、compile.sh が両方の javac の呼び出しを
# 通る (踏み台の javac と、その踏み台が java_rules_skylark.bzl の genrule で
# 呼ぶ JDK の javac)。
#
# 使い方: run-dist.sh <proc-full.patch>
#   DIST_VER   既定 9.3.0rc1。<ver> で releases/download/<ver>/bazel-<ver>-dist.zip
#   MODE       patched (既定): 当てて建て、bazel が出来て version を答えるか
#              control        : 当てずに建て、bazel が出来ないことを確かめる
#                               (JDK 23 以降でのみ意味がある)
set -eu

PATCH=$1
DIST_VER=${DIST_VER:-9.3.0rc1}
MODE=${MODE:-patched}
WORK=${WORK:-$PWD/bootstrap-work}
URL="https://github.com/bazelbuild/bazel/releases/download/${DIST_VER}/bazel-${DIST_VER}-dist.zip"

echo "=== JDK / OS"
"${JAVA_HOME:?JAVA_HOME を設定してください}/bin/javac" -version
uname -sm

# macOS の clang は module map を持つので cc_configure が layering_check を
# 立て、grpc がその検査に通らない (thread_count.cc が module を export して
# いないと言って落ちる)。当て物とは無関係の C++ の問題で、master-bootstrap.sh
# が DragonFly に対してするのと同じく、踏み台を建てる間だけ切る。
case "$(uname -s)" in
Darwin) EXTRA_BAZEL_ARGS="--features=-layering_check"; export EXTRA_BAZEL_ARGS ;;
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

if [ "$MODE" = patched ]; then
	echo "=== 当て物を当てる"
	patch -p1 -f -i "$PATCH" </dev/null
	grep -q -- '-proc:full' scripts/bootstrap/compile.sh \
		|| { echo "compile.sh に -proc:full が入っていない"; exit 1; }
	n=$(grep -c 'javacopt=-proc:full' scripts/bootstrap/bootstrap.sh)
	[ "$n" -eq 2 ] || { echo "bootstrap.sh の -proc:full が $n 行 (2 のはず)"; exit 1; }

	echo "=== bootstrap (patched)"
	env bash ./compile.sh > compile.log 2>&1 || true
	if built; then
		"$(bazel_bin)" version | grep -i 'build label'
		echo "RESULT patched $(uname -s) JDK$($JAVA_HOME/bin/javac -version 2>&1 | sed 's/javac //') OK"
	else
		echo "当て物ありでも bazel が出来なかった"
		grep -n 'error:\|errors$\|ERROR' compile.log | tail -20
		exit 1
	fi
else
	echo "=== bootstrap (control: 素のまま。JDK 23 以降では bazel が出来ないはず)"
	env bash ./compile.sh > compile.log 2>&1 || true
	if built; then
		echo "素のまま働く bazel が出来てしまった。この JDK では当て物が要らない"
		"$(bazel_bin)" version | grep -i 'build label'
		exit 1
	fi
	echo "--- bazel が出来なかった。理由を確かめる"
	if grep -q 'AutoOneOf_DependencyError' compile.log; then
		echo "RESULT control OK: 一段目 (compile.sh の javac) で AutoOneOf が無いと言って落ちた"
	elif grep -q 'AutoValue_JarOwner' compile.log; then
		echo "RESULT control OK: 二段目 (genrule の javac) で AutoValue が無いと言って落ちた"
	else
		echo "bazel は出来なかったが、想定した annotation processor のエラーが log に無い"
		grep -n 'error:' compile.log | head -10
		exit 1
	fi
fi
