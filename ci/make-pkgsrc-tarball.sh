#!/bin/bash
#
# pkgsrc ツリーを取ってきて、ゲストが /usr の下に展開するだけの tar.gz に
# する。中身の先頭は pkgsrc/ で、自作カテゴリ zakinko を重ねてある。
#
#	PKGSRC_SHA		取る commit (既定: trunk の先端)
#	ZAKINKO_PKGSRC_URL	自作カテゴリ。空なら重ねない
#
# ゲストには git が無い (base に入っていない) ので、ツリーの用意はホスト側の
# 仕事。ここで作ったものを seed の HTTP 越しに取りに来る。
#
# 上流は CVS (anoncvs@anoncvs.NetBSD.org:/cvsroot) で、GitHub のこれは変換
# ミラー。ビルドにはミラーで足りるが、「上流でもう直っているか」を確かめる
# ときは CVS を見ること。doc/upstream/ を参照。

set -euo pipefail

cd "$(dirname "$0")/.."
. ci/vm.sh

: "${ZAKINKO_PKGSRC_URL:=https://github.com/zakinko/pkgsrc-zakinko}"

mkdir -p "$SEED_DIR"
out=$SEED_DIR/pkgsrc.tar.gz

sha=${PKGSRC_SHA:-}
if [ -z "$sha" ]; then
	echo "=== trunk の先端を調べる"
	sha=$(git ls-remote https://github.com/NetBSD/pkgsrc trunk | cut -f1)
fi
echo "=== pkgsrc $sha"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pkgsrc.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

git init -q "$tmp/pkgsrc"
git -C "$tmp/pkgsrc" remote add origin https://github.com/NetBSD/pkgsrc
git -C "$tmp/pkgsrc" fetch -q --depth 1 origin "$sha"
git -C "$tmp/pkgsrc" checkout -q FETCH_HEAD
rm -rf "$tmp/pkgsrc/.git"

if [ -n "$ZAKINKO_PKGSRC_URL" ]; then
	if git clone -q --depth 1 "$ZAKINKO_PKGSRC_URL" "$tmp/pkgsrc/zakinko"; then
		rm -rf "$tmp/pkgsrc/zakinko/.git"
		echo "=== zakinko カテゴリを重ねた"
	else
		echo "!! $ZAKINKO_PKGSRC_URL を clone できなかった。自作分は作られない。" >&2
	fi
fi

## 当て物は zakinko カテゴリの中に zakinko/<pkg> として入っている。上流の
## 位置へ焼き込むことはもうしない。上で clone した時点でツリーに乗っている。
##
## 以前は overlay/<カテゴリ>/<パッケージ> を上流の同じ場所へ上書きしていた。
## あれは上流の package そのものを差し替えるので、それに依存する側にも効いた。
## 平らにしたことでその性質は無くなっている。zakinko/augeas を入れても
## sysutils/augeas は素のままなので、素から建てたときに依存で引かれるのは
## 上流の方になる。効かせたい相手には先に zakinko/<pkg> を入れること。
##
if [ ! -d "$tmp/pkgsrc/zakinko" ]; then
	echo "!! zakinko カテゴリが無い。当て物の入っていないものが出来上がる。" >&2
	echo "   ZAKINKO_PKGSRC_URL を確かめること。" >&2
	exit 1
fi
echo "=== zakinko カテゴリ: $(ls -d "$tmp"/pkgsrc/zakinko/*/ 2>/dev/null | wc -l | tr -d ' ') 件"

echo "=== 固める"
# macOS で作ると全ファイルに com.apple.provenance が付き、NetBSD 側の tar が
# 一件ごとに "Cannot restore extended attributes" を吐く (15 万行) 上に、
# 終了ステータスまで非ゼロになる。拡張属性は最初から入れない。
tar_noxattr -czf "$out" -C "$tmp" pkgsrc
ls -lh "$out"
echo "$sha" >"$SEED_DIR/pkgsrc.sha"
