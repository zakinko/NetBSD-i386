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

##
## 上流 pkgsrc への当て物 (overlay) をツリーに焼き込む。
##
## 実体は pkgsrc-zakinko の overlay/ に置く。pkgsrc に関するものは向こうに
## 集める、という分担。zakinko/ はカテゴリとして展開されるので、overlay/ は
## package と間違われないよう、当てたあとツリーから取り除く。
##
## ここで焼き込むのは、キャッシュの効き方のため。pkgsrc.tar.gz の鍵には
## pkgsrc-zakinko の HEAD が入っているので、向こうを直せば必ず作り直される。
## 別便で渡していた頃は overlay だけ鍵に入らず、直しても古いまま走った。
##
## 当てた場所は .overlay-dirs に残す。ゲスト側はそれを見て makepatchsum を
## 走らせる (patch を足したら distinfo に SHA1 が要るため)。
##
overlay_src=
if [ -d "$tmp/pkgsrc/zakinko/overlay" ]; then
	overlay_src=$tmp/pkgsrc/zakinko/overlay
	echo "=== overlay: pkgsrc-zakinko のものを使う"
elif [ -d overlay ]; then
	overlay_src=$PWD/overlay
	echo "!! overlay: pkgsrc-zakinko に無いので、この repo のものを使う" >&2
	echo "   (移行が済んだらこちらの overlay/ は消すこと)" >&2
fi

: >"$tmp/pkgsrc/.overlay-dirs"
if [ -n "$overlay_src" ]; then
	for d in $(cd "$overlay_src" && find . -mindepth 2 -maxdepth 2 -type d |
	           sed 's|^\./||' | sort); do
		if [ ! -d "$tmp/pkgsrc/$d" ]; then
			echo "!! overlay: $d が pkgsrc に無い。飛ばす。" >&2
			continue
		fi
		( cd "$overlay_src/$d" && tar cf - . ) |
		    ( cd "$tmp/pkgsrc/$d" && tar xf - )
		echo "$d" >>"$tmp/pkgsrc/.overlay-dirs"
		echo "    $d"
	done
	rm -rf "$tmp/pkgsrc/zakinko/overlay"
fi
echo "=== overlay を当てた: $(wc -l <"$tmp/pkgsrc/.overlay-dirs" | tr -d ' ') 件"

echo "=== 固める"
# macOS で作ると全ファイルに com.apple.provenance が付き、NetBSD 側の tar が
# 一件ごとに "Cannot restore extended attributes" を吐く (15 万行) 上に、
# 終了ステータスまで非ゼロになる。拡張属性は最初から入れない。
tar_noxattr -czf "$out" -C "$tmp" pkgsrc
ls -lh "$out"
echo "$sha" >"$SEED_DIR/pkgsrc.sha"
