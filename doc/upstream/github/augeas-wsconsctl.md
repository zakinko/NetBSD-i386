# augeas: OpenBSD の wsconsctl.conf のパスを直す

| | |
|---|---|
| 上流 | [hercules-team/augeas](https://github.com/hercules-team/augeas) |
| 枝 | `wsconsctl-conf-typo` ([zakinko/augeas](https://github.com/zakinko/augeas)) |
| 触るもの | `lenses/simplevars.aug` |
| 大きさ | 1 ファイル、1 行 |
| PR | **未提出** |
| pkgsrc 側 | `overlay/sysutils/augeas/patches/patch-wsconsctl-conf-typo` |

## なぜ

`Simplevars` の filter にこう書いてある。

```
           . incl "/etc/mixerctl.conf"
           . incl "/etc/wsconsctlctl.conf"
```

`ctl` が一つ多い。**2013-01-10 の `aa3bc264`「Add two files found on OpenBSD
to the simplevars lens.」で入って以来、何にも一致していない。** 作者は
OpenBSD の Jasper Lievisse Adriaanse で、同じ commit で入った
`/etc/mixerctl.conf` の方は正しい。

OpenBSD に実在するのは `/etc/wsconsctl.conf` で、`/etc/rc` が適用している。

```sh
# Apply wsconsctl.conf(5) settings.
wsconsctl_conf() {
	[[ -x /sbin/wsconsctl ]] || return
	stripcom /etc/wsconsctl.conf |
	while read _line; do
		eval "wsconsctl $_line"
```

中身は `wsconsctl(8)` の変数代入が 1 行に 1 つ。

```
keyboard.encoding=ru
display.screen_off=60000
```

## 確かめたこと

キーに入る `.` は `Rx.word` (`/[A-Za-z0-9_.-]+/`) が既に許しているので、
`Simplevars` はこのままで解釈できる。

```
{ "keyboard.encoding" = "ru" }
{ "display.screen_off" = "60000" }
{ "mouse.reverse_scrolling" = "1" }
```

`augparse` は 232 本の lens テストすべてを通る。

## NetBSD は無関係

NetBSD には `/etc/wsconsctl.conf` が無い。あるのは `/etc/wscons.conf` で、
`rc.d/wscons` が読む別物 (`font` や `screen` の指定であって代入ではない)。
どの lens も見ていない。

## adduser の件と分けた理由

同じ `simplevars.aug` の同じ filter を触るので束ねられるが、分けてある。
[augeas-adduser-conf.md](augeas-adduser-conf.md) の方は三つの OS の挙動を
論じる変更で議論になりうる。こちらは読めば終わる。束ねると後者が前者の
人質になる。

pkgsrc の overlay では両方を当てるので、patch は当たる順に気を付けること
(`patch-adduser-...` → `patch-wsconsctl-...` の順で、名前の並びがそのまま
正しい順になっている)。
