# augeas: man ページを、設定された lens ディレクトリに向ける

| | |
|---|---|
| 上流 | [hercules-team/augeas](https://github.com/hercules-team/augeas) |
| 枝 | `man-lens-directory` ([zakinko/augeas](https://github.com/zakinko/augeas)) |
| 触るもの | `man/Makefile.am` |
| 大きさ | 1 ファイル、11 行 |
| PR | [#892](https://github.com/hercules-team/augeas/pull/892) |
| pkgsrc 側 | `patch-man_Makefile.in` |

## なぜ

`augtool.1`、`augparse.1`、`augmatch.1`、`augprint.1` はいずれも lens が
`/usr/share/augeas/lenses` にあると書いている。実際に道具が探すのは
`AUGEAS_LENS_DIR` で、これは `src/internal.h` が `DATADIR` から作り、
`DATADIR` は configure が `$(datadir)` から設定する。

したがってこの記述が正しいのは `--prefix=/usr` で configure したときだけで、
それ以外では嘘になる。既定の `/usr/local`、pkgsrc の `/usr/pkg` や
`/opt/pkg`、`--prefix` が言うとおりのどこか。

該当は **15 箇所**。

```
augtool.1  5    augmatch.1 5    augprint.1 4    augparse.1 1
```

## 何をするか

`man/Makefile.am` に `install-data-hook` を足し、install 時に
`/usr/share/augeas` を `$(datadir)/augeas` へ書き換える。

`.pod` ではなく install したページを書き換えるのは、ソースを読み物として
素のまま残すためと、余計な build 段を要らなくするためである。置換すべき
ことはパスが決まるまで無く、それは install 時である。

## 確かめたこと

実物の man 4 本に対して、`--prefix=/opt/pkg` の staging へ install した。

| | `/usr/share/augeas` | `/opt/pkg/share/augeas` |
|---|---|---|
| GNU make | 0 箇所 | 15 箇所 |
| BSD make | 0 箇所 | 15 箇所 |

当て物 12 本を当てた実物の augeas でも、`make install` 後に同じ結果になる。

## pkgsrc 側

もともと `SUBST_CLASSES` で `pre-configure` に `man/*.1` と `man/*.pod` を
書き換えていたが、**上流に出したものと形を揃えるため patch に替えた**。
`patch-man_Makefile.in` は automake が生成するとおりの三箇所を入れる。

1. `install-data-hook:` の本体
2. `install-data-am:` から `$(MAKE) $(AM_MAKEFLAGS) install-data-hook` を呼ぶ行
3. `.PHONY` への追加

**generated file に hook を足すときは、この配線まで要る。** automake は
`Makefile.am` に hook があるときだけ呼び出しを生成するので、本体だけ書いても
呼ばれない。形は `man/Makefile.am` に #892 を当てて `autoreconf` を回し、
その出力から拾った。手で考えた形ではない。

## OpenBSD の ports との関係

同じ理由で `augparse.1` を `pre-configure` の `SUBST_CMD` で書き換えている。
`patch-man_augparse_1` がそれで、#892 が入れば不要になる。
