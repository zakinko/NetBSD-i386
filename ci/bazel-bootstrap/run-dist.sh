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
#   MODE       patched (既定): 当てて建て、成功と version を確かめる
#              control        : 当てずに建て、既知の場所で落ちることを確かめる
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

rm -rf "$WORK"
mkdir -p "$WORK/src"
echo "=== $URL を取る"
curl -fsSL -o "$WORK/dist.zip" "$URL"
( cd "$WORK/src" && unzip -q ../dist.zip )
cd "$WORK/src"

if [ "$MODE" = patched ]; then
	echo "=== 当て物を当てる"
	patch -p1 -f -i "$PATCH" </dev/null
	grep -q -- '-proc:full' scripts/bootstrap/compile.sh \
		|| { echo "compile.sh に -proc:full が入っていない"; exit 1; }
	n=$(grep -c 'javacopt=-proc:full' scripts/bootstrap/bootstrap.sh)
	[ "$n" -eq 2 ] || { echo "bootstrap.sh の -proc:full が $n 行 (2 のはず)"; exit 1; }

	echo "=== bootstrap (patched)"
	env bash ./compile.sh
	echo "=== version"
	./output/bazel version
	./output/bazel version | grep -q '^Build label:' \
		|| { echo "Build label が出ない"; exit 1; }
	echo "RESULT patched $(uname -s) JDK$($JAVA_HOME/bin/javac -version 2>&1 | sed 's/javac //') OK"
else
	echo "=== bootstrap (control: 素のまま。JDK 23 以降では落ちるはず)"
	if env bash ./compile.sh > compile.log 2>&1; then
		echo "素のまま建ってしまった。この JDK では当て物が要らない"
		tail -3 compile.log
		exit 1
	fi
	echo "--- 落ちた。理由を確かめる"
	if grep -q 'AutoOneOf_DependencyError' compile.log; then
		echo "RESULT control OK: 一段目 (compile.sh の javac) で AutoOneOf が無いと言って落ちた"
	elif grep -q 'AutoValue_JarOwner' compile.log; then
		echo "RESULT control OK: 二段目 (genrule の javac) で AutoValue が無いと言って落ちた"
	else
		echo "落ちたが、想定した annotation processor のエラーではない"
		grep -n 'error:' compile.log | head -10
		exit 1
	fi
fi
