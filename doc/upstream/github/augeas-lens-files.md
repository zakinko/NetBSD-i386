# augeas: ファイルを並べるのに GNU make を要るのをやめる

| | |
|---|---|
| 上流 | [hercules-team/augeas](https://github.com/hercules-team/augeas) |
| 枝 | `lens-files-without-gnu-make` ([zakinko/augeas](https://github.com/zakinko/augeas)) |
| 触るもの | `configure.ac` / `Makefile.am` / `man/Makefile.am` / `tests/Makefile.am` / `doc/naturaldocs/Makefile.am` |
| 大きさ | 5 ファイル、23 行 |
| PR | [#889](https://github.com/hercules-team/augeas/pull/889) |
| pkgsrc 側 | `patch-configure` と `patch-Makefile.in` |

**この一連の作業の本題。** `augeas` の audit を消そうとして掘ったら、
pkgsrc が 2014 年から lens を一本も入れていないことが分かった。

## なぜ

上流の `Makefile.am` にこう書いてある。

```make
dist_lens_DATA=$(wildcard lenses/*.aug)
dist_lenstest_DATA=$(wildcard lenses/tests/*.aug)
```

`$(wildcard)` は GNU make の関数である。それ以外の make は呼び出しを文字列の
まま残すので、変数には名前の一覧ではなく `$(wildcard lenses/*.aug)` が入り、
`make install` は何にも一致しない。**lens は一本も入らず、`augtool` は設定
ファイルを一つも読めない。**

NetBSD 11.0/amd64 に pkgsrc の公式パッケージを入れた実機で、
`augtool print /files/etc/hosts` が何も返さないことを確認している。

`$(wildcard)` は他に三箇所あるが、いずれも `EXTRA_DIST` の中で `make dist`
にしか効かない。それも同じ理由で壊れているので、まとめて直した。

| 場所 | 何 | 影響 |
|---|---|---|
| `Makefile.am` | `dist_lens_DATA` | **build/install を壊す** |
| `man/Makefile.am` | `EXTRA_DIST` | `make dist` のみ |
| `tests/Makefile.am` | `EXTRA_DIST` | `make dist` のみ |
| `doc/naturaldocs/Makefile.am` | `EXTRA_DIST` | `make dist` のみ |

## 何をするか

数が多いもの (lens 231 + 231、tests/modules 62) は configure で glob して
`AC_SUBST` で埋める。少ないもの (man の pod 4 本、naturaldocs の conf 8 本)
は名前を書き出す。automake の作法としてはこちらが素直である。

**`Makefile.am` に素の glob を書くのでは足りない。** in-tree なら通るが、
ソース外ビルドで壊れる。automake は各項目を

```
for p in $$list; do if test -f "$$p"; then d=; else d="$(srcdir)/"; fi
```

で入れるが、この代替は `$$p` が実在の名前でないと働かない。パターンのままでは
builddir にも srcdir にも見つからず、本数はまた 0 に戻る。configure には
この分岐が無い。`$srcdir` がそこでは分かっているためである。

## 確かめたこと

lens 三本と lens テスト三本を用意し、staging ディレクトリへ install した。

| | GNU make | BSD make |
|---|---|---|
| in-tree | 6 | 6 |
| 別の build ディレクトリ | 6 | 6 |
| *現行のコード* | *6* | *0* |

`make dist` も最上位と部分木の両方で確かめ、どちらの make でも同じ配布物が
できる。実物の augeas でも、当て物を当てて `make install` すると **lens が
462 本**入る。

## この依存が払わせているもの

BSD はいずれも GNU make を base に持っていない。

| | どうしているか |
|---|---|
| FreeBSD ports | `USES` に `gmake` |
| OpenBSD ports | `USE_GMAKE= Yes` |
| pkgsrc | 足していない。だから lens が 0 本 |

pkgsrc が足すとなると `devel/gmake` を建てることになる。`.aug` を並べて
置くためだけに make をもう一つ建てる依存である。

## pkgsrc 側が上流と形が違う理由

上流は `configure.ac` と `Makefile.am` を直すが、pkgsrc が当てているのは
`configure` と `Makefile.in`、つまり生成物である。ソースを当てると
`autoreconf` が要り、`autoconf` は `help2man` を、`automake` は `autoconf` と
`perl` と `gm4` を連れてくる。gmake 一つを嫌ったのに五つ建てるのでは筋が
通らない。Fedora と OpenBSD も生成物を当てている。Debian と FreeBSD は元から
`autoreconf` を回すので、あちらはソースを当てている。

**ソースだけ当てて autoreconf を回さない、という中間の手は無い。** 生成物が
素のままなので効かないうえ、`Makefile.am` の方が新しくなって automake の
再生成規則が発火し、`aclocal` が無いところで build が止まる。実際に試した。
