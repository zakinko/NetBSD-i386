#!/bin/sh
# bazel の dist archive の bootstrap script を POSIX sh 版に差し替えて、bash では
# なく sh (dash) だけで通しで bootstrap する。scripts/bootstrap の bash→sh 化
# (posix-sh.patch) が実際に建つことを CI で見るためのもの。
#
# bazel 自身が genrule の action に使う shell も既定は /bin/bash なので、
# --shell_executable=/bin/sh でそちらも sh に向ける。これで build 全体を通して
# bash を呼ばない。JDK 21 で回す (sh 化を -proc:full から切り離す)。
#
# 使い方: run-posix-sh.sh <posix-sh.patch>
set -eu

PATCH=$1
DIST_VER=${DIST_VER:-9.3.0rc1}
WORK=${WORK:-$PWD/posix-sh-work}
URL="https://github.com/bazelbuild/bazel/releases/download/${DIST_VER}/bazel-${DIST_VER}-dist.zip"

echo "=== JDK / OS / sh"
"${JAVA_HOME:?JAVA_HOME を設定してください}/bin/javac" -version
uname -sm
# /bin/sh が bash でない実物であることを見せる (Debian/Ubuntu は dash)
ls -l /bin/sh || true

rm -rf "$WORK"
mkdir -p "$WORK/src"
echo "=== $URL を取る"
curl -fsSL -o "$WORK/dist.zip" "$URL"
( cd "$WORK/src" && unzip -q ../dist.zip )
cd "$WORK/src"

echo "=== bootstrap script を POSIX sh 版へ差し替える (posix-sh.patch)"
patch -p1 -f -i "$PATCH" </dev/null
for f in compile.sh scripts/bootstrap/compile.sh scripts/bootstrap/buildenv.sh \
         scripts/bootstrap/bootstrap.sh; do
	head -1 "$f" | grep -q '^#!/bin/sh$' \
		|| { echo "$f の shebang が #!/bin/sh でない"; exit 1; }
	grep -nE '^[[:space:]]*function |\[\[|=\(' "$f" \
		&& { echo "$f に bash 専用構文が残っている"; exit 1; }
done
echo "  4 本とも #!/bin/sh、bash 専用構文なし"

# bazel の genrule も sh で回す。/bin/bash に依らないことを示す。
EXTRA_BAZEL_ARGS="--shell_executable=/bin/sh"; export EXTRA_BAZEL_ARGS

echo "=== sh ./compile.sh で bootstrap (bash を呼ばない)"
sh ./compile.sh > compile.log 2>&1 || true

if [ -x output/bazel ] && ./output/bazel version 2>/dev/null | grep -q '^Build label:'; then
	./output/bazel version | grep -i 'build label'
	echo "RESULT posix-sh $(uname -s) OK: sh だけで bootstrap 完走"
else
	echo "sh だけの bootstrap で bazel が出来なかった"
	echo "--- command not found / Exit の類"
	grep -n -i 'command not found\|not found\|No such file\|Exit 12[0-9]\|bad substitution\|Syntax error' compile.log | tail -20
	echo "--- 末尾 60 行"
	tail -60 compile.log
	exit 1
fi
