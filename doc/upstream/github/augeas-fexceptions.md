# augeas: -fexceptions を使う前に personality がリンクできるか確かめる

| | |
|---|---|
| 上流 | [hercules-team/augeas](https://github.com/hercules-team/augeas) |
| 枝 | `fexceptions-link-check` ([zakinko/augeas](https://github.com/zakinko/augeas)) |
| 触るもの | `acinclude.m4` |
| 大きさ | 1 ファイル、14 行 |
| PR | [#891](https://github.com/hercules-team/augeas/pull/891) |
| pkgsrc 側 | `patch-configure` (#889 と同居) |

## なぜ

`AUGEAS_COMPILE_WARNINGS` は、`main()` が空のプログラムを compile+link して
各フラグの可否を決めている。**`-fexceptions` についてはそれで何も決まらない。**
空の `main()` には例外表が無いので `__gcc_personality_v0` を名指すことがなく、
フラグは受理され、本体のリンクが後で落ちる。

OpenBSD 7.9/amd64 の clang 19.1.7 でまさにそうなる。configure はフラグを
使えると報告し、そのあとで:

```
ld: error: undefined symbol: _Unwind_GetLanguageSpecificData
>>> referenced by gcc_personality_v0.c:203
>>>   gcc_personality_v0.o:(__gcc_personality_v0)
>>>   in archive /usr/lib/libcompiler_rt.a
```

`libcompiler_rt.a` は personality を持っているが、`_Unwind_*` は `libc++abi`
にしか無く、C のプログラムはそれを繋がない。1.14.1 の tarball はそこで組めず、
二つのフラグを外せば組める。

## 「古い版のバグ」ではなかった

最初、この当て物は古い環境の名残ではないかと疑った。**外れた。**

フラグは **2007-11-26 の `aa5a92fe`「Autotools support for building」**から
入っていて、augeas 側は 18 年変わっていない。OpenBSD 側も材料が揃ったままで、
7.9/amd64 の実測はこうだった。

```
/usr/lib/libc.so.103.0        _Unwind_* を  0 個
/usr/lib/libc++abi.so.9.0     _Unwind_* を 18 個   ← C++ 側にしかない
/usr/lib/libcompiler_rt.a     988056 バイト、健在
libunwind*                    無し
```

変わったのは linker だけで、`undefined reference to` (bfd ld) が
`ld: error: undefined symbol:` (lld) になった。**症状は 8 年そのまま。**

## 検査の形が効く

どう書けば実際に落ちるのかを OpenBSD 7.9 で測った。

| 検査用プログラム | フラグ無し | フラグ有り |
|---|---|---|
| 空の `main()` — いま configure が使っているもの | 通る | 通る |
| `__attribute__((cleanup))` を使うもの | 通る | 通る |
| `__gcc_personality_v0` を名指すもの | **落ちる** | **落ちる** |

**二つの系を区別できるのは三つめだけ。** しかもフラグの有無に関わらず同じ
答えを返すので、前提条件として使える。Ubuntu の runner (glibc) では同じ
プログラムがリンクできる。`cleanup` 属性を使えば例外表が出るだろうという
読みは外れた。

## 何をするか

`AC_LINK_IFELSE` で routine 自体を要求し、リンクできなければ `common_flags`
を空にする。リンクできる環境では何も変わらない。glibc は libgcc に持っている
し、FreeBSD 14.3 はフラグをそのままにして組める。

## pkgsrc 側

上流は `acinclude.m4` を直すが、pkgsrc は生成物を当てるので `configure` に
同じ検査を入れている。autoconf 2.71 が生成する形 (`ac_fn_c_try_link`、
`$as_nop`、`printf "%s\n"`) に合わせて書いた。**手書きの生成コードなので、
上流に入ったらすぐ消すこと。**

pkgsrc-on-OpenBSD で実際に落ちるかは、まだ tarball 直組みでしか見ていない。
bootstrap 版は `devel/pkgconf` が OpenBSD 7.9 で segfault して configure まで
届かなかった。OpenBSD は base に pkgconf を持っている (`usr.bin/pkgconf` の
`PROG` が `pkg-config`) ので、`TOOLS_PLATFORM.pkg-config` でそちらを使わせて
やり直している。
