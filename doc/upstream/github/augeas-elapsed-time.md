# augeas: 経過時間を、それを収められる型で持つ

| | |
|---|---|
| 上流 | [hercules-team/augeas](https://github.com/hercules-team/augeas) |
| 枝 | `elapsed-is-not-a-time` ([zakinko/augeas](https://github.com/zakinko/augeas)) |
| 触るもの | `src/augtool.c` / `examples/dump.c` |
| 大きさ | 2 ファイル、6 行 |
| PR | [#890](https://github.com/hercules-team/augeas/pull/890) |
| pkgsrc 側 | `patch-src_augtool.c` と `patch-examples_dump.c` |

## なぜ

`print_time_taken()` がミリ秒の値を `time_t` に入れている。

```c
time_t elapsed = (stop->tv_sec - start->tv_sec)*1000
               + (stop->tv_usec - start->tv_usec)/1000;
printf("Time: %ld ms\n", elapsed);
```

**`time_t` はそのためのものではない。** この値は経過時間であって時刻ではないし、
ミリ秒の計数にどれだけの幅が要るかは、その環境の時計の型とは何の関係もない。
`%ld` も、`time_t` がたまたま `long` である環境でしか正しくない。

NetBSD 11.0/i386 では `long` が 4 バイト、`time_t` が 8 バイトで、gcc 12.5.0 が
こう言う。この package は `-Wall -Wformat` 付きで組まれるので、自ら求めた警告
である。

```
t.c:6:21: warning: format '%ld' expects argument of type 'long int',
          but argument 2 has type 'time_t' {aka 'long long int'} [-Wformat=]
    6 |     printf("Time: %ld ms\n", elapsed);
      |                   ~~^        ~~~~~~~
      |                   %lld
```

OpenBSD も同じ立場で、`time_t` は全アーキテクチャで `__int64_t`
(`sys/sys/_types.h`) なので 32bit のものが該当する。

## 表示される値は、実際には壊れない

ここは誇張しないこと。i386 は引数をスタックで渡し、`%ld` はその下位半分を
読むので、計数が 2^32 ms — およそ **49 日** — を超えるまでは数が合う。
NetBSD 11.0/i386 での実測。

```
期待 1234          %ld -> 1234          長い方 -> 1234
期待 4294967296    %ld -> 0             長い方 -> 4294967296
期待 5000000000    %ld -> 705032704     長い方 -> 5000000000
期待 -1            %ld -> -1            長い方 -> -1
```

`augtool` の一コマンドが 49 日かかることは、まずない。**これは型と警告に
対する修正であって、利用者が目にしそうな何かに対するものではない。** PR の
本文にもそう書いた。隠して「値が壊れる」と書けば、49 日の話を指摘された
時点で信用を失う。

## 何をするか

変数を `long long` で宣言する。書式のずれも一緒に片付き、呼び出し側の
キャストも要らない。同じ機械で確かめて、警告は出ず値もそのまま出る。

OpenBSD の ports はこの二行を当て物として抱えているが、書式だけ `%lld` に
変えて変数は `time_t` のままにしている。`time_t` が常に 64bit である OpenBSD
ではそれで正しいが、`time_t` が `long` である環境では誤りになる。たとえば
FreeBSD/i386 の `time_t` は 32bit である (`sys/x86/include/_types.h`)。

## 測り方

`netbsd-ci-images` に i386 のイメージが 6.1.5 から 11.0 まである。
[ci/netbsd-i386-format.sh](../../../ci/netbsd-i386-format.sh) がそれを起動して、
pkgsrc を通さずに `print_time_taken()` を写した五行を直に組む。手元の pkgsrc
には既に当て物が入っているので、`build.yml` では警告の出る状態を作れない。

`vmactions` には i386 の BSD イメージが無い。Ubuntu で
`-m32 -D_TIME_BITS=64` を使えば「`long` 32bit / `time_t` 64bit」は作れるが、
実機で採れるならそちらがよい。
