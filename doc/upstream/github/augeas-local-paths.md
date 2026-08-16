# augeas: PostgreSQL と rsyslog の /usr/local のパスを足す

| | |
|---|---|
| 上流 | [hercules-team/augeas](https://github.com/hercules-team/augeas) |
| 枝 | `bsd-local-paths` ([zakinko/augeas](https://github.com/zakinko/augeas)) |
| 触るもの | `lenses/pg_hba.aug` / `lenses/postgresql.aug` / `lenses/rsyslog.aug` |
| 大きさ | 3 ファイル、4 行 |
| PR | [#888](https://github.com/hercules-team/augeas/pull/888) |
| pkgsrc 側 | `patch-lenses_pg_hba.aug` ほか 2 本 |

## なぜ

三つの filter が、Linux ディストリビューション以外の環境に実在するファイルを
取りこぼしている。

**`/usr/local/pgsql/data` は PostgreSQL 自身の既定である。** インストール文書の
"Short Version" にそう書いてある。

```
mkdir -p /usr/local/pgsql/data
/usr/local/pgsql/bin/initdb -D /usr/local/pgsql/data
```

したがって既定の prefix でソースから入れた者は、**OS を問わず**ここに置く。
`Pg_Hba` と `Postgresql` は Red Hat 系と Debian 系の配置を持っているが、
これは持っていない。FreeBSD 固有の話ではない。

**`/usr/local/etc` は BSD が自ら配っていないソフトの設定を置く場所である。**
この種の lens で持っていないのは `Rsyslog` だけだった。

## 前例がある

master の **15 本**の lens が既に `/usr/local` のパスを持っている。

```
dovecot  nginx  php  postfix_{main,master,virtual,transport,access,passwordmap,sasl_smtpd}
puppet  puppet_auth  puppetfileserver  sudoers  systemd
```

`3d886ff Add ocsinventory-agent.cfg to SimpleVars (#637)` のように、filter に
パスを一行足すだけの commit も通っている。取り込まれる見込みは高い。

## pkgsrc への影響

同じ 15 本が `/usr/local` を決め打ちしているので、**pkgsrc では全部外れる**。
pkgsrc の設定は `${PKG_SYSCONFDIR}`、既定で `${PREFIX}/etc`、つまり
`/usr/pkg/etc` である。

```
上流の lens        /usr/local/etc/nginx/nginx.conf
pkgsrc の実際      /usr/pkg/etc/nginx/nginx.conf     ← どの lens も見ていない
```

man のパス ([augeas-man-paths.md](augeas-man-paths.md)) と同じ構図で、上流に
静的なパスを足しても `/usr/local` しか救えない。prefix は実行環境で決まるので、
そこは packager 側の仕事になる。FreeBSD が `post-patch` の `REINPLACE` で
puppet 系にやっているのがそれである。

**この PR はそこまでやらない。** `/usr/local` を足すところまでで、pkgsrc の
`${PREFIX}` に寄せる話は別に考えること。lens の filter には生成の仕組みが
無いので、`SUBST` で `/usr/local` を `${PREFIX}` に書き換えるのが手だが、
FreeBSD ports と併用する環境では困る。まだ結論は出していない。

## 確かめたこと

`augparse` が 232 本の lens テストすべてを通る。パスを足すだけなので、
既存の解釈は変わらない。
