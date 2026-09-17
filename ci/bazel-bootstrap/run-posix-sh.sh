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
#   SH_BIN  compile.sh を回す shell と、bazel の genrule に渡す shell。
#           既定 /bin/sh。busybox の ash を測るなら /bin/busybox ash ではなく
#           ash への path を渡す (例 /usr/bin/ash)。
set -eu

PATCH=$1
DIST_VER=${DIST_VER:-9.3.0rc1}
SH_BIN=${SH_BIN:-/bin/sh}
WORK=${WORK:-$PWD/posix-sh-work}
URL="https://github.com/bazelbuild/bazel/releases/download/${DIST_VER}/bazel-${DIST_VER}-dist.zip"

echo "=== JDK / OS / sh"
"${JAVA_HOME:?JAVA_HOME を設定してください}/bin/javac" -version
uname -sm
# 使う shell の実体を見せる (Debian/Ubuntu の /bin/sh は dash、Alpine は busybox)
ls -l /bin/sh || true
echo "SH_BIN=$SH_BIN"
"$SH_BIN" -c 'echo "  この shell: $0"' || true
# bash が在るか無いかを記録する。無い箱で通ることが要点。
if command -v bash >/dev/null 2>&1; then
	echo "  bash: $(command -v bash) (在るが使わない)"
else
	echo "  bash: 無い"
fi

rm -rf "$WORK"
mkdir -p "$WORK/src"
echo "=== $URL を取る"
curl -fsSL -o "$WORK/dist.zip" "$URL"
( cd "$WORK/src" && unzip -q ../dist.zip )
cd "$WORK/src"

echo "=== bootstrap script を POSIX sh 版へ差し替える (posix-sh.patch)"
patch -p1 -f -i "$PATCH" </dev/null
for f in compile.sh scripts/bootstrap/compile.sh scripts/bootstrap/buildenv.sh \
         scripts/bootstrap/bootstrap.sh src/zip_builtins.sh; do
	head -1 "$f" | grep -q '^#!/bin/sh$' \
		|| { echo "$f の shebang が #!/bin/sh でない"; exit 1; }
	grep -nE '^[[:space:]]*function |\[\[|=\(' "$f" \
		&& { echo "$f に bash 専用構文が残っている"; exit 1; }
done
echo "  5 本とも #!/bin/sh、bash 専用構文なし"

# bazel の genrule も同じ shell で回す。/bin/bash に依らないことを示す。
EXTRA_BAZEL_ARGS="--shell_executable=$SH_BIN"
# macOS の clang は module map を持つので cc_configure が layering_check を立て、
# grpc がその検査に通らない。shell とは無関係の C++ の問題なので切る
# (run-dist.sh の Darwin と同じ扱い)。
case "$(uname -s)" in
Darwin) EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --features=-layering_check" ;;
esac
export EXTRA_BAZEL_ARGS

echo "=== $SH_BIN ./compile.sh で bootstrap (bash を呼ばない)"
"$SH_BIN" ./compile.sh > compile.log 2>&1 || true

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
