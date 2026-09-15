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
	export PKG_PATH="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$(uname -m)/$(uname -r | cut -d_ -f1)/All"
	for p in git-base openjdk21 python313 unzip zip; do
		pkg_add -U "$p" || say "pkg_add $p が入らなかった"
	done
	;;
FreeBSD|GhostBSD)
	env ASSUME_ALWAYS_YES=yes pkg install -y git openjdk21 python3 unzip zip || true
	;;
DragonFly)
	pkg install -y git openjdk21 python3 unzip zip || true
	;;
OpenBSD)
	export PKG_PATH="https://cdn.openbsd.org/pub/OpenBSD/$(uname -r)/packages/$(uname -m)/"
	for p in git jdk-21 python-3 unzip zip; do
		pkg_add -I "$p" || say "pkg_add $p が入らなかった"
	done
	;;
*)
	say "知らない OS: $OS"
	exit 1
	;;
esac

# JDK の在処は OS ごとに違う。決め打ちせず、在るものから新しい順に採る。
JAVA_HOME=""
for d in $(ls -d /usr/pkg/java/openjdk* /usr/local/openjdk* /usr/local/jdk-* \
                 /usr/lib/jvm/* 2>/dev/null | sort -r); do
	if [ -x "$d/bin/javac" ]; then JAVA_HOME=$d; break; fi
done
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
export WORK=$W/dist
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
for p in "$WORK/output/bazel" "$SRCDIR/output/bazel" "$W/dist/output/bazel"; do
	[ -x "$p" ] && { B=$p; break; }
done
[ -n "$B" ] || { say "踏み台の bazel が見つからない"; exit 1; }
echo "踏み台: $B"
"$B" --version

# set -e の下で `[ ... ] && { ...; }` を素で置くと、偽のときにその AND 列の
# 終了値が 1 になって script ごと終わる。if で書く。
if [ "$STAGE" = bootstrap ]; then
	say "段 bootstrap まで完了"
	exit 0
fi

##### 4. master を建てる #####
echo '##### 4. upstream master を建てる #####'
export B
export SRC=$W/mst
export PATCH859=$SRCDIR/ci/rules_cc_859.patch
[ -f "$SRCDIR/ci/rules_python_quote_args.patch" ] && \
	export PATCH_RULES_PYTHON=$SRCDIR/ci/rules_python_quote_args.patch
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
