# augeas: /etc/adduser.conf を Simplevars へ移す

| | |
|---|---|
| 上流 | [hercules-team/augeas](https://github.com/hercules-team/augeas) |
| 枝 | `adduser-conf-simplevars` ([zakinko/augeas](https://github.com/zakinko/augeas)) |
| 触るもの | `lenses/shellvars.aug` / `lenses/simplevars.aug` / `lenses/tests/test_simplevars.aug` |
| 大きさ | 3 ファイル、30 行 (うち 29 行はテスト) |
| PR | [#893](https://github.com/hercules-team/augeas/pull/893) |
| pkgsrc 側 | `overlay/sysutils/augeas/patches/patch-lenses_shellvars.aug` ほか 2 本 |

## なぜ

`/etc/adduser.conf` は `Shellvars` の filter に入っている。だがこのファイルを
配っている三つの系のうち、**shell script として扱っているのは FreeBSD だけ**
である。

| | adduser(8) の実装 | 読み方 | Shellvars で |
|---|---|---|---|
| OpenBSD | perl | 行を `eval` | **parse_failed** |
| Debian | perl | 正規表現 | **黙って消える** |
| FreeBSD | /bin/sh | `. "${ADDUSERCONF}"` | 正しい |
| NetBSD | **無い** | `useradd(8)` が `/etc/usermgmt.conf` | 無関係 |

**OpenBSD** の `usr.sbin/adduser/adduser.perl` の `config_read` は

```perl
if (s/^(\w+\s*=\s*\()/\@$1/ || s/^(\w+\s*=)/\$$1/) {
    eval $_;
}
```

と、行をそのまま perl として `eval` する。だから書き出されるものも perl。

```
verbose = 1
defaultpasswd = "yes"
path = ('/bin', '/usr/bin', '/usr/local/bin')
```

`Shellvars` はこれを解釈できず、41 行目 (`path = (...)`) で落ちる。

```
/augeas/files/etc/adduser.conf/error = "parse_failed"
/augeas/files/etc/adduser.conf/error/line = "41"
/augeas/files/etc/adduser.conf/error/lens = ".../shellvars.aug:251.12-.60:"
```

**Debian** の `AdduserCommon.pm` の `read_config` は

```perl
m/^\s*([_a-zA-Z0-9]+)\s*=\s*([-a-zA-Z0-9_\/\.^\$\]\[*?+\|@\\^":\)\(~,\s]*)/
```

で読む。`=` の前後の空白を許し、囲みの引用符を外す。`Shellvars` はその形を
**拒否せず、コマンドとして読む**。これが厄介で、error も出ないまま設定が
消える。

```
DSHELL = /bin/bash

  { "@command" = "DSHELL"
    { "@arg" = "= /bin/bash" } }
```

**FreeBSD** だけが本当に shell で、`usr.sbin/adduser/adduser.sh` が
`. "${ADDUSERCONF}"` と source している。

## 何をするか

`Simplevars` は Debian の parser が受ける文法そのもので、perl のリストは
不透明な値として保持する。パスを移すのに要るのは 1 行。

この木は **1 パス = 1 lens** を不変条件にしていて (231 本の filter を突き
合わせて重複ゼロを確認した)、OS 別の条件分岐を書く手立ては無い。逃げ道は
「パスが OS 固有なら専用 lens」だけで、`bootconf.aug` (OpenBSD の
`/etc/boot.conf`) や `solaris_system.aug` がそれにあたる。`/etc/adduser.conf`
は共有パスなので使えない。三つの書式の実体が `key = value` の範囲に収まって
いて、`Simplevars` がその共通部分だった、というのがこの PR の要点である。

なお `Simplevars` は既に `/etc/mixerctl.conf` と `/etc/wsconsctlctl.conf` を
持っていて、BSD のファイルを見る前例がある (後者は綴りが誤っている →
[augeas-wsconsctl.md](augeas-wsconsctl.md))。

## 確かめたこと

それぞれの系が **実際に生成する** ファイルで見た。

| | 前 | 後 |
|---|---|---|
| OpenBSD、`adduser(8)` が書いたもの | `parse_failed` | 17 件 |
| Debian 3.152、配布されている設定をすべて有効化 | 31 件 | **木は同一** |
| FreeBSD、`save_config()` が書いたもの | 11 件 | **木は同一** |

無変更で save すると三つとも 1 バイトも変わらず、一つ設定を変えるとその行
だけが書き換わる。perl のリストも往復する。

```
$ augtool --autosave -e "set /files/etc/adduser.conf/shellpref \"('sh', 'ksh')\""
```

失われるのは、単なる代入を超えた shell の構文。このファイルにありうる形の
うち違いが出るのは **`export` だけ**で、`defaultgroups="wheel operator"` も
`homeprefix=/home/$company` も両方の lens で同じに読める。`export` は
FreeBSD の `adduser` の使い方を変えない (自分の shell に source するため)。

`augparse` は 232 本の lens テストすべてを通る。NetBSD 9.4 / 10.1 / 11.0 の
i386 で `PASS: lens-simplevars.sh`。

## OpenBSD の ports との関係

OpenBSD は 2016 年から `patch-lenses_shellvars_aug` を抱えていて、理由書きは

> adduser.conf is not a shell script, so don't try to parse it as such.
> rc.conf* are not shell scripts anymore.

同じ見立てである。ただしあちらは **filter から消すだけ**で、それでは Debian と
FreeBSD でこのファイルが失われる。上流に出されないまま残ったのはそのため
だと思われる。

同じ patch が消している `/etc/rc.conf` と `/etc/rc.conf.local` の方は、
**もう要らない**。現行の `Shellvars` は OpenBSD の実物の `rc.conf` を素で
通す (`match /augeas//error` に何も出ず、`apmd_flags = "NO"` が読め、行末
コメントも拾える)。`patch-lenses_simplelines_aug` も同じ理由で用済み。
OpenBSD に伝えること。

## 素材の在処

再現に使ったものは手元の scratchpad にある。消えていたら次で作り直せる。

```
OpenBSD の雛形   usr.sbin/adduser/adduser.perl の config_write (1589 行あたり)
Debian の実物    https://sources.debian.org/data/main/a/adduser/3.152/adduser.conf
Debian の parser 同 AdduserCommon.pm の read_config (166 行あたり)
FreeBSD の雛形   usr.sbin/adduser/adduser.sh の save_config (173 行あたり)
```

`augtool -r <root> -e '...'` で、`<root>/etc/adduser.conf` を置いた偽の root
に対して試せる。lens を差し替えて比べるときは `-I` では既定のパスが勝つので、
入っている木の方を直接いじること (一度これで空振りした)。
