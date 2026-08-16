# 上流プロジェクトへ送るもの

一つ上の [doc/upstream](..) は **pkgsrc へ**送るもの (`send-pr`、メール) を
置くところ。ここはその先、**package が包んでいるソフト自体の上流**へ送る
ものを置く。pkgsrc に patch を当てるのは手元をすぐ直すためで、patch を
消せるようにするには上流に入れてもらうしかない。

pkgsrc 自身がそう言っている。`pkgsrc/bootstrap/README` の "PER PLATFORM
INFORMATION" にこうある。

> Note also that pkgsrc policy is that fixes to packages, unless the
> fixes are to adjust a package to pkgsrc norms, should be filed
> upstream and the upstream tracker URL included in the patch file or
> Makefile.

だから overlay の patch header には、上流へ出したものの参照を書く。番号が
決まる前は fork の枝名を書いておき、PR を開いたら番号に差し替える。

## 決まりごと

- **一件一 PR。** 束ねない。議論になるものと、読めば終わるものを一緒に
  すると、後者が前者の人質になる。
- **文面は英日を並べて出し、承認を待つ。** `gh pr create` はそのあと。
- **commit は `Signed-off-by:` を付けるかどうかを先に調べる。**
  `CONTRIBUTING` / `HACKING` / CI が求めているか、直近 50 commit のうち
  何本が実際に付けているか。使っていない project に持ち込まない。
- **写してきた patch には署名しない。** DCO は自分の成果に対するもの。

## 今あるもの

| | 上流 | 状態 |
|---|---|---|
| [augeas-adduser-conf.md](augeas-adduser-conf.md) | hercules-team/augeas | 枝 `adduser-conf-simplevars` を push 済み。**PR 未提出** |
| [augeas-wsconsctl.md](augeas-wsconsctl.md) | hercules-team/augeas | 枝 `wsconsctl-conf-typo` を push 済み。**PR 未提出** |

fork は [zakinko/augeas](https://github.com/zakinko/augeas)。どちらも
master から 1 commit で、互いに独立している。

## どうやって確かめているか

**上流 augeas の CI は死んでいる。** `.github/workflows/build.yml` の
`runs-on:` が `ubuntu-20.04` のままで、その runner はもう無い。2026-01 以降の
run は全て 24 時間 runner を待って cancelled になっている。

```
24113481590  master  push  2026-04-08  cancelled  24h0m2s
24112915007  master  push  2026-04-08  cancelled  24h0m2s
build: The job has exceeded the maximum execution time
       while awaiting a runner for 24h0m0s
```

したがって **PR を出しても Build は赤くなる。変更のせいではない。** 相手に
「通りました」と言うには、こちらで回した結果を添えるしかない。回し方は二つ
用意してある。

**一つめが NetBSD 側。** [pkgsrc-zakinko の
overlay/sysutils/augeas](https://github.com/zakinko/pkgsrc-zakinko/tree/main/overlay/sysutils/augeas)
に上流へ出すものと同じ patch を置き、`TEST_TARGET=check` があるので
[build.yml](../../../.github/workflows/build.yml) の `make test` が augeas
自身の `make check` を回す。9.4 / 10.1 / 11.0 の i386 三つで走る。

**二つめが BSD 側。** [augeas-bsd.yml](../../../.github/workflows/augeas-bsd.yml)
が OpenBSD と FreeBSD で pkgsrc を bootstrap し、そこで建てる。lens の
filter は NetBSD には対象のファイルが無いので、実際に効くところを見るには
これが要る。手で起動する。

### bootstrap で引っかかったこと

`pkgsrc/bootstrap/bootstrap` に **`digest` の字は一つも無い。** bootstrap が
入れるのは bmake と pkg_install までで、`$PREFIX/bin/digest` は入らない。
`make makepatchsum` はそれを呼ぶので、当て物の SHA1 を distinfo に入れる段で
止まる。`pkgtools/digest` を先に建てること。NetBSD では既に入っているため
気付けない。

OpenBSD の VM は `/` が 986M しかない。空いているのは `/home` (113G) と
`/usr` (16.9G) の方で、pkgsrc の木をうっかり `/` に置くと展開の途中で溢れる。

bootstrap は失敗しても 0 を返すことがある。終了状態だけを見ず、`bmake` と
`digest` が実際に入ったかを見て止めること。
