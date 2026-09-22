#!/bin/sh
# runner の container: 機能を使わずに docker run で回す箱の中で走る入口。
#
# runner は container: の中へ自分の node を差し込んで動くが、その node は
# glibc 向けで、musl の箱では alpine と分かったときだけ musl 版に替える。
# Void や Chimera は ID が alpine ではないので glibc の node が exec で落ち、
# job は道具を入れる前に死ぬ。openSUSE の leap は像に sh が無く、runner が
# 最初に打つ sh -c で落ちる。どちらも runner の作りの問題で、bootstrap の
# 話ではないので、その箱だけ docker run で素の image を起こし、中で
# この script が linux-tools.sh と bootstrap-dist-sh.sh を順に呼ぶ。
#
# linux-tools.sh は JAVA_HOME と JAVA_VERSION を GITHUB_ENV へ書く作りなので、
# ここでは file を一つ渡して読み戻す。
#
# 使い方: linux-in-docker.sh <workspace> <dist.zip>
set -eu
WS=$1; DIST=$2
cd "$WS"
GITHUB_ENV=$WS/.docker-env; : > "$GITHUB_ENV"; export GITHUB_ENV
IN_DOCKER=1; export IN_DOCKER
# leap の像には sh が無い。道具が入るまでは、起こした shell (IN_SHELL) で呼ぶ。
"${IN_SHELL:-sh}" ci/bazel-bootstrap/linux-tools.sh
while IFS='=' read -r k v; do
	[ -n "$k" ] && export "$k=$v"
done < "$GITHUB_ENV"
echo "/bin/sh -> $(readlink -f /bin/sh)  JAVA_HOME=${JAVA_HOME:-}  JAVA_VERSION=${JAVA_VERSION:-}"
exec sh ci/bazel-bootstrap/bootstrap-dist-sh.sh "$DIST"
