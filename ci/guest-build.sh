#!/bin/sh
#
# VM の中で走るビルド本体。ホストから ssh で叩かれる。
#
# 前提: ホストが http://10.0.2.2:8123/ に
#   pkgsrc.tar.gz     展開すると /usr/pkgsrc になる pkgsrc ツリー (zakinko 入り)
#   mk.conf           sbin/mk.conf (techne の /etc/mk.conf の写し)
#   mk.conf.ci        CI でだけ効かせる追加分
#   roles             作る役割の一覧
#   sbin.tar.gz       ~/.sbin の写し (list.pkg.*)
#   prev-packages.tar 前回作った All/*.tgz (なくてもよい)
# を置いている。
#
# 作るものは roles と sbin/list.pkg.* から決まる。一覧の正は techne の
# ~/.sbin で、ここにあるのはその写し。

set -u

# ssh 越しに sh を直接叩かれるのでログインシェルの初期化が走らない。
# pkg_info などが PATH に無い状態で始まるので、ここで揃える。
PATH=/usr/pkg/sbin:/usr/pkg/bin:/sbin:/usr/sbin:/bin:/usr/bin
export PATH

SEED=http://10.0.2.2:8123
PKGSRCDIR=/usr/pkgsrc
PACKAGES=$PKGSRCDIR/packages
DISTDIR=$PKGSRCDIR/distfiles

# GitHub の 6 時間で殺されると何も持ち帰れない。手前で自分から降りて、
# 作れたところまでを公開する。残りは次回に回る。
BUILD_DEADLINE_MIN=${BUILD_DEADLINE_MIN:-280}
DEADLINE=$(($(date +%s) + BUILD_DEADLINE_MIN * 60))

NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)

log() { echo "=== $*"; }
die() { echo "!! $*" >&2; exit 1; }

fetch() { ftp -V -o "$2" "$SEED/$1"; }

log "CPU=$NCPU 期限=$(date -r "$DEADLINE" 2>/dev/null || echo "+${BUILD_DEADLINE_MIN}min")"

##
## 1. pkgsrc ツリー
##
if [ ! -f $PKGSRCDIR/mk/bsd.pkg.mk ]; then
	log "pkgsrc を展開する"
	fetch pkgsrc.tar.gz /tmp/pkgsrc.tar.gz || die "pkgsrc.tar.gz を取れない"
	rm -rf $PKGSRCDIR
	# tar は属性の復元に失敗しただけでも非ゼロを返すことがある。展開できた
	# かどうかは終了ステータスではなく中身で判断する。文句は別に取っておく。
	( cd /usr && tar xzpf /tmp/pkgsrc.tar.gz ) 2>/tmp/pkgsrc-extract.err
	rm -f /tmp/pkgsrc.tar.gz
	if [ ! -f $PKGSRCDIR/mk/bsd.pkg.mk ]; then
		sed -n '1,20p' /tmp/pkgsrc-extract.err >&2
		die "pkgsrc を展開できなかった"
	fi
	if [ -s /tmp/pkgsrc-extract.err ]; then
		log "展開時の文句 $(wc -l </tmp/pkgsrc-extract.err | tr -d ' ') 行 (/tmp/pkgsrc-extract.err)"
	fi
fi

##
## 2. overlay の当たり先
##
## 上流 pkgsrc がまだ取り込んでいない当て物は、ホスト側で pkgsrc ツリーに
## 焼き込んだうえで渡ってくる (ci/make-pkgsrc-tarball.sh)。実体は
## pkgsrc-zakinko の overlay/。ここでは当たった場所の一覧を受け取るだけ。
##
if [ -f $PKGSRCDIR/.overlay-dirs ]; then
	cp $PKGSRCDIR/.overlay-dirs /tmp/overlay-dirs
	n=$(wc -l </tmp/overlay-dirs | tr -d ' ')
	log "overlay が当たっているもの $n 件"
	[ "$n" -gt 0 ] && sed 's/^/    /' /tmp/overlay-dirs
else
	: >/tmp/overlay-dirs
	log "overlay はない"
fi

##
## 3. 設定
##
log "mk.conf を置く"
fetch mk.conf /tmp/mk.conf || die "mk.conf を取れない"
fetch mk.conf.ci /tmp/mk.conf.ci || die "mk.conf.ci を取れない"
{
	cat /tmp/mk.conf
	echo
	sed "s|@MAKE_JOBS@|$NCPU|" /tmp/mk.conf.ci
} >/etc/mk.conf
chmod 644 /etc/mk.conf

##
## 作るものを決める。roles に書いた役割ぶんの sbin/list.pkg.<役割> を
## 順に連結する。行頭 + で始まる行は役割ではなく PKGPATH の直書き。
##
## list.pkg.* の書式は ~/.sbin/pkgsrc-bootstrap.sh に合わせてある:
##   PKGPATH [make のオプション] [post_action]
## 先頭の空白・空行・# 始まりは無視。#! で始まる行は向こうの
## PKG_WORK_AROUND 用なので、ここでは読み飛ばす。
##
fetch roles /tmp/roles || die "roles を取れない"
fetch sbin.tar.gz /tmp/sbin.tar.gz || die "sbin.tar.gz を取れない"
rm -rf /tmp/sbin && mkdir -p /tmp/sbin
tar xzf /tmp/sbin.tar.gz -C /tmp/sbin 2>/dev/null
[ -d /tmp/sbin/sbin ] || die "sbin.tar.gz の中身が想定と違う"

: >/tmp/pkglist
while read -r name _rest; do
	case "$name" in ''|\#*) continue ;; esac
	case "$name" in
	+*)
		echo "${name#+}" >>/tmp/pkglist
		continue
		;;
	esac
	l=/tmp/sbin/sbin/list.pkg.$name
	[ -f "$l" ] || die "役割 $name に対応する list.pkg.$name が無い"
	n=$(LC_ALL=C grep -cvE '^[[:space:]]*(#|$)' "$l" || true)
	log "役割 $name ($n 行)"
	LC_ALL=C sed -e 's/#.*//' -e 's/[[:space:]].*//' "$l" |
	    LC_ALL=C grep -v '^$' >>/tmp/pkglist
done </tmp/roles

## 同じものが複数の役割に出てくる (sudo が sh と local の両方など)。
sort -u /tmp/pkglist >/tmp/pkglist.u && mv /tmp/pkglist.u /tmp/pkglist
log "作る対象 $(wc -l </tmp/pkglist | tr -d ' ') 件"

mkdir -p "$PACKAGES/All" "$DISTDIR" /var/tmp/pkgsrc.work

## overlay で足した patch の SHA1 を distinfo に入れる。mk.conf が要るので
## ここまで来てから走らせる。
if [ -s /tmp/overlay-dirs ]; then
	## makepatchsum は pkgtools/digest の digest を呼ぶ。入れたばかりの
	## システムには無く、無いと黙って SHA1 を書かずに成功したふりをする。
	if [ ! -x /usr/pkg/bin/digest ]; then
		log "makepatchsum のために pkgtools/digest を入れる"
		( cd "$PKGSRCDIR/pkgtools/digest" && make install ) ||
		    die "pkgtools/digest を入れられない"
	fi

	while read -r d; do
		[ -n "$d" ] || continue
		log "makepatchsum $d"
		( cd "$PKGSRCDIR/$d" && make makepatchsum ) ||
		    die "$d の makepatchsum に失敗"

		## 本当に書けたか確かめる。書けていないまま進むと
		## patch のチェックサム不一致でビルドが止まる。
		for p in "$PKGSRCDIR/$d"/patches/patch-*; do
			[ -e "$p" ] || continue
			b=${p##*/}
			grep -q "SHA1 ($b)" "$PKGSRCDIR/$d/distinfo" ||
			    die "$d/distinfo に $b の SHA1 が入らなかった"
		done
	done </tmp/overlay-dirs
fi

##
## 4. 前回のパッケージ
##
## これが差分ビルドの種。前回と同じ版のものは .tgz が既にあるので作り直さない。
##
## ftp(1) は 404 でも本文を書いて 0 を返すことがあるので、tar として読めるか
## を見てから展開する。
if fetch prev-packages.tar /tmp/prev.tar 2>/dev/null &&
   tar tf /tmp/prev.tar >/dev/null 2>&1; then
	log "前回のパッケージを戻す"
	( cd "$PACKAGES" && tar xpf /tmp/prev.tar )
	log "  $(ls "$PACKAGES/All" | grep -c '\.tgz$' || echo 0) 個"
else
	log "前回のパッケージはない。全部作る。"
fi
rm -f /tmp/prev.tar

##
## 5. 何を作るのか数える
##
## pkglist は PKGPATH の一覧でしかないので、それぞれの PKGNAME を pkgsrc に
## 聞く。150 個で 5 分ほどかかるが、これがないと「もうある」の判定ができない。
##
log "PKGNAME を数える"
: >/tmp/wanted
: >/tmp/missing
while read -r pkgpath _rest; do
	case "$pkgpath" in ''|\#*) continue ;; esac
	if [ ! -d "$PKGSRCDIR/$pkgpath" ]; then
		echo "$pkgpath" >>/tmp/missing
		continue
	fi
	pkgname=$(cd "$PKGSRCDIR/$pkgpath" && make show-var VARNAME=PKGNAME 2>/dev/null)
	if [ -z "$pkgname" ]; then
		echo "$pkgpath" >>/tmp/missing
		continue
	fi
	echo "$pkgpath $pkgname" >>/tmp/wanted
done </tmp/pkglist

log "  作る対象 $(wc -l </tmp/wanted | tr -d ' ') 個 / pkgsrc にないもの $(wc -l </tmp/missing | tr -d ' ') 個"
[ -s /tmp/missing ] && { log "pkgsrc に見当たらない PKGPATH:"; sed 's/^/    /' /tmp/missing; }

##
## 6. 古い版の .tgz を捨てる
##
## 版が上がったものが前回の .tgz のまま残っていると、pkg_summary に古い方も
## 載って pkgin が迷う。同じ PKGBASE で PKGNAME の違うものだけ消す。
##
while read -r _pkgpath pkgname; do
	base=${pkgname%-*}
	for f in "$PACKAGES/All/$base"-[0-9]*.tgz; do
		[ -e "$f" ] || continue
		[ "${f##*/}" = "$pkgname.tgz" ] && continue
		log "古い ${f##*/} を捨てる"
		rm -f "$f"
	done
done </tmp/wanted

##
## 7. 既にある .tgz は入れてしまう
##
## 依存として要るものを毎回ソースから組み直さないため。
##
## PKG_PATH は pkg_add の呼び出しにだけ効かせる。環境に置きっぱなしにすると
## pkgsrc が「PKG_PATH を消してから作業しろ」と言って全パッケージが落ちる
## (bsd.pkg.mk の can-be-built-here.mk)。
log "既にある .tgz を入れる"
while read -r _pkgpath pkgname; do
	[ -f "$PACKAGES/All/$pkgname.tgz" ] || continue
	pkg_info -qe "$pkgname" 2>/dev/null && continue
	PKG_PATH=$PACKAGES/All pkg_add -U "$PACKAGES/All/$pkgname.tgz" \
	    >/dev/null 2>&1 || true
done </tmp/wanted

##
## 8. ビルド
##
: >/tmp/failed
: >/tmp/built
status=complete

while read -r pkgpath pkgname; do
	[ -f "$PACKAGES/All/$pkgname.tgz" ] && continue

	if [ "$(date +%s)" -ge "$DEADLINE" ]; then
		log "時間切れ。ここまでを持ち帰る。残りは次回。"
		status=incomplete
		break
	fi

	log "build $pkgpath ($pkgname)"
	if ( cd "$PKGSRCDIR/$pkgpath" && make package-install </dev/null ); then
		echo "$pkgname" >>/tmp/built
		( cd "$PKGSRCDIR/$pkgpath" && make clean ) >/dev/null 2>&1
	else
		log "FAILED $pkgpath"
		echo "$pkgpath $pkgname" >>/tmp/failed
	fi
done </tmp/wanted

##
## 9. pkg_summary
##
## pkgin はリポジトリの直下にこれがあることだけを期待している。
##
cd "$PACKAGES/All" || die "$PACKAGES/All がない"
rm -f pkg_summary pkg_summary.xz pkg_summary.gz pkg_summary.bz2
set -- ./*.tgz
if [ -e "$1" ]; then
	log "pkg_summary を作る ($# 個)"
	pkg_info -X "$@" >pkg_summary || die "pkg_info -X に失敗"
	xz -9 pkg_summary
else
	log "パッケージが一つも無いので pkg_summary は作らない"
fi

cat >/tmp/ci-report <<EOF
status=$status
wanted=$(wc -l </tmp/wanted | tr -d ' ')
built=$(wc -l </tmp/built | tr -d ' ')
failed=$(wc -l </tmp/failed | tr -d ' ')
packages=$(ls | grep -c '\.tgz$')
EOF

log "結果"
sed 's/^/    /' /tmp/ci-report
if [ -s /tmp/failed ]; then
	log "作れなかったもの"
	sed 's/^/    /' /tmp/failed
fi

sync
exit 0
