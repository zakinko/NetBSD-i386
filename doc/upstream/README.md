# 上流 pkgsrc へ送るもの

2026-08-14 に **CVS HEAD で確認済み**。三つとも誰も直していない。

pkgsrc の正は CVS (`anoncvs@anoncvs.NetBSD.org:/cvsroot`) で、GitHub の
NetBSD/pkgsrc は変換ミラー。確認は CVS 側でやること。今回は
[CVSweb](https://cvsweb.netbsd.org/bsdweb.cgi/pkgsrc/) と、techne 上の
anoncvs チェックアウトの両方で見ている。

| 見たもの | CVS HEAD | 上流の実物 |
|---|---|---|
| `textproc/libxml2/Makefile.common` | rev 1.31, libxml2-2.15.1 | 2.15.3 (2026-04-15) |
| `devel/ncurses/Makefile` | rev 1.124, ncurses-6.6 | 6.6 で修正入り。版は最新 |
| `sysutils/augeas/Makefile` | rev 1.20, 1.14.1 PKGREVISION=1, patches なし | master に修正あり・未リリース |

## 送るもの

| 宛先 | 中身 | 添えるもの |
|---|---|---|
| pkgsrc-users@NetBSD.org | libxml2 を 2.15.3 へ | [libxml2.mail](libxml2.mail) + [libxml2.diff](libxml2.diff) |
| bsiegert@NetBSD.org (cc pkgsrc-users@) | augeas の CVE-2025-2588 | [augeas.mail](augeas.mail) + [augeas.diff](augeas.diff) |
| pkgsrc-security@NetBSD.org | ncurses と libxml2 のエントリを絞る | [pkg-vulnerabilities.mail](pkg-vulnerabilities.mail) |

**ビルド確認は済んでいる。** 2026-08-14、NetBSD 11.0/i386 (qemu) の上で
pkgsrc trunk `fa7ad771` に対して両方を通した:

```
augeas-1.14.1nb2.tgz     patch-src_fa.c 適用済み
libxml2-2.15.3.tgz       patch-configure はそのまま当たる
```

依存も含めて 12 パッケージが失敗ゼロで揃った。だから `.mail` の
"Built and packaged on NetBSD 11.0/i386" は事実。手順は
[ci/run-local.sh](../../ci/run-local.sh) で再現できる。

`pkg-vulnerabilities` は公開の pkgsrc モジュールに無い (CVSweb で 404)。
pkgsrc-security@ が持っているので、メールで頼むしかない。

送り方は素のメールでよい。PR の形にするなら techne に `send-pr` があるので
`send-pr -f pkg` でカテゴリ `pkg`。宛先は gnats-bugs@NetBSD.org になる。
メンテナが分かっているもの (augeas の bsiegert@) は直接送る方が早い。

## diff の作り直し

techne の `~/pkgsrc-cvs` に anoncvs のチェックアウトが置いてある。200K の
使い捨てで、`/usr/pkgsrc` の代わりではない (`mk/` も `bootstrap` も無いので
何もビルドできない)。要るときに作り直せばよい。

```sh
ssh zakinko@techne.fml.org
mkdir -p ~/pkgsrc-cvs && cd ~/pkgsrc-cvs
env CVS_RSH=ssh cvs -q -d anoncvs@anoncvs.NetBSD.org:/cvsroot \
    co -P pkgsrc/textproc/libxml2 pkgsrc/sysutils/augeas
cd pkgsrc
# 直してから
env CVS_RSH=ssh cvs -q diff -u textproc/libxml2
env CVS_RSH=ssh cvs -q diff -u sysutils/augeas
```

パッケージ単位で切り出せるので、submission のために pkgsrc ツリー全体を
CVS で持つ必要はない。

新しく足したファイル (`patches/patch-src_fa.c`) は anoncvs では
`cvs add` できないので、`diff -u /dev/null <file>` で作って
`Index:` ヘッダを手で足してある。当たることは新規チェックアウトで
`patch -C -p0` して確認済み。

CVS HEAD が動いたら、当たるかどうかを確認し直すこと。

## 取り込まれたら

`overlay/textproc/libxml2` と `overlay/sysutils/augeas` を消す。消し忘れると、
上流が直したあとも古い写しを使い続けることになる。
