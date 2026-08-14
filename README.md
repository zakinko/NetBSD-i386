# NetBSD-i386

NetBSD/i386 のバイナリパッケージを GitHub Actions で作って、Releases に置く。
手元の箱は `pkgin` でそこを見るだけにする。

## なぜ

ディスクが 21GB しかない箱で pkgsrc を回すと、ツリーと distfiles と work
ディレクトリだけで数 GB 持っていかれる。ビルドは外でやって、結果だけ受け取る
方が筋がいい。

公式のバイナリパッケージ (cdn.NetBSD.org) をそのまま使えば済む話ではない。
`mk.conf` で `apache24` の `suexec` を有効に `http2` を無効に、`ng` の
`canna` を無効に……といったオプションを指定していて、公式のビルドとは中身が
違うから。だから**自分の `mk.conf` で作ったものを、自分のリポジトリから配る**
必要がある。

## 仕組み

```
  techne の ~/.sbin          このリポジトリ         GitHub Actions        手元の箱
  ┌──────────────┐          ┌────────────┐      ┌────────────────┐     ┌────────┐
  │ list.pkg.*   │─写し────>│ sbin/      │─────>│ ubuntu-latest  │     │ NetBSD │
  │ /etc/mk.conf │  (正)    │ roles      │      │ └qemu i386     │     │  i386  │
  └──────────────┘          └────────────┘      │   └make package│     │ pkgin  │
        ↑                    nb-sync-sbin       └───────┬────────┘     └───▲────┘
     ここを直す                                        │ *.tgz          │
                                                        ▼                 │
                                                 ┌─────────────────┐      │
                                                 │ Releases        │──────┘
                                                 │ pkgsrc-11.0-i386│  https で取るだけ
                                                 └─────────────────┘
```

**何を作るかの正は techne の `~/.sbin`** (CVS: `elena.sh.fml.org:/cvsroot` の
`ahodori/hostconf/home/.sbin`)。GitHub Actions からはその CVS にも
`~fukachan/etc/mk.conf` にも届かないので、`sbin/` にその写しを置いて CI に
読ませている。**`sbin/` を直接編集しないこと。** 直すのは `.sbin` の側で、
`bin/nb-sync-sbin` で追従させる。

i386 が使える出来合いの Action は無い (`vmactions/netbsd-vm` は amd64,
aarch64, riscv64, sparc64 のみ)。なので
[anita](https://www.gson.org/netbsd/anita/) で NetBSD/i386 を qemu に入れた
イメージを一度だけ作り、以後はそれを使い回す。anita は sysinst の出力を
シリアルコンソールから読んで答えを流し込む道具で、NetBSD 本家のテストでも
使われている。

ホストが x86_64 でゲストが i386 なので KVM が効く。エミュレーションではなく
ほぼ素の速さで回る。

### 差分ビルド

前回のリリースに置いた `*.tgz` を毎回 VM に戻してから始める。**リリース自体が
キャッシュ**になっていて、版が変わっていないものは作り直さない。GitHub の
6 時間制限に当たりそうになるとゲスト側が自分から降りて、そこまでを公開する。
もう一度回せば続きから進む。

## どのリリース向けか

**リリースが変わると libc のメジャーが変わるので、作ったバイナリは他の
リリースでは動かない。** 箱ごとに OS が違うので、リリースごとに別々に作って
別々のタグに置く。

```
pkgsrc-9.4-i386     techne など 9.4 の箱
pkgsrc-10.1-i386    移行前の箱
pkgsrc-11.0-i386    移行後
```

作る対象は `.github/workflows/build.yml` の `matrix.release` の一行だけ。
`fail-fast: false` にしてあるので、片方が落ちてももう片方は最後まで走る。

箱の側は**自分で選ぶ**。`bin/nb-update` が `uname -r` と `uname -m` から
タグを組み立てるので、設定は要らない。まだ作られていないリリースの箱で
`nb-update setup` を叩くと、`pkg_summary.xz` の有無を先に確かめて止まる。

### 10.1 の箱を 11.0 に上げるときの順番

順番を間違えると、上げた直後にパッケージが全部動かない箱が残る。

1. CI に **11.0 用**を作らせておく。`matrix.release` に入っていれば勝手に
   走る。**ここまでは箱を触らない。**
2. 箱を `~/.sbin/sysupgrade.sh` で 11.0 に上げる。
3. `nb-update setup` してから `nb-update`。

`nb-update` は `uname -r` を見るので、上げる前に叩いても 10.1 のリポジトリを
見るだけで壊れない。上げたあとに叩けば自動的に 11.0 の方を向く。**設定を
書き換える必要はない。**

## 初回

### 1. GitHub に置く

**public であること。** `pkgin` は素の HTTP GET しかできず、認証を通せない。

### 2. まず四つだけ通す

`roles` には `base` と `sh`、それに自作のものが書いてある。この状態で一度
Actions を回して、VM が立って `.tgz` がリリースに並ぶところまで確認する。
ここが通れば、あとは役割を足すだけ。

初回はベースイメージの作成 (anita で NetBSD を入れる) が入るので 30 分ほど
余分にかかる。二回目以降はキャッシュから来る。

### 3. NetBSD の箱を向ける

このリポジトリを箱にも置いて、

```sh
sudo ./bin/nb-update setup
```

`/usr/pkg/etc/pkgin/repositories.conf` がこのリリースを指すようになる。既存の
ファイルは `.bak.<日付>` に退避され、公式リポジトリの行は**コメントアウトされ
る**。混ぜると、オプションの効いていない方のバイナリを掴むことがあるため。

`/etc/mk.conf` はここでは触らない。**`~/.sbin/pkgsrc-fix-mkconf.sh` の仕事**
なので、そちらに任せる。

### 4. 役割を足す

`roles` に足して push するだけ。

```
base
sh
www        ← 足す
local      ← 足す
```

名前は `sbin/list.pkg.<名前>` に対応する。一覧そのものを変えたいときは
techne の `~/.sbin` を直して `bin/nb-sync-sbin` で追従させる。

150 個を空から作ると数時間かかる。一回で終わらなければ、Actions をもう一度
回せば続きから進む。

## 普段

```sh
sudo nb-update check     # 何が上がるか見るだけ
sudo nb-update           # 更新する
```

`nb-update` は毎週日曜 03:17 JST に CI が回った後に叩けばよい。
pkgsrc ツリーは要らないので、この箱でソースを引くことはもうない。

`/usr/pkgsrc` と `/var/tmp/pkgsrc.work` を消せる。これが本題のディスクの話。

audit は `~/.sbin` の `make audit` (`pkgsrc-audit.sh`) を使う。

## 中身

| ファイル | 何か |
|---|---|
| `sbin/` | techne の `~/.sbin` の写し。**直接編集しない**。`list.pkg.*` と `mk.conf` |
| `roles` | この CI がどの役割ぶんを作るか。`sbin/list.pkg.<名前>` を選ぶ |
| `bin/nb-sync-sbin` | `.sbin` から `sbin/` を取り直す |
| `ci/mk.conf.ci` | CI でだけ効かせる分 (置き場所、並列度)。中身は変えない設定だけ |
| `doc/upstream/` | 上流 pkgsrc へ送る diff とメール |
| `ci/make-base-image.sh` | anita で NetBSD/i386 のベースイメージを作る |
| `ci/guest-bootstrap.sh` | 入れたばかりの VM を ssh で叩ける状態にする |
| `ci/vm.sh` | ホスト側から VM を扱う小道具 |
| `ci/guest-build.sh` | VM の中で走るビルド本体 |
| `ci/run-local.sh` | 手元で同じ手順を回す |
| `bin/nb-pkglist` | 箱に入っているものの PKGPATH を出す。`list.pkg.*` との突き合わせ用 |
| `bin/nb-update` | 箱の pkgin を回す |
| `doc/audit.md` | `pkg_admin audit` に出ているものの棚卸し |

## `~/.sbin` との分担

向こうは「pkgsrc ツリーがある箱で、ソースから建てる」ための道具立て。こちらは
「pkgsrc ツリーの無い箱に、外で作ったバイナリを配る」ための道具立て。同じ
ことを二回書かないよう、重なる部分は向こうに寄せてある。

| | どこ |
|---|---|
| 何を作るか (`list.pkg.*`) | **`~/.sbin`**。ここは写しを読むだけ |
| `/etc/mk.conf` の中身と配布 | **`~/.sbin`** (`pkgsrc-fix-mkconf.sh`) |
| audit | **`~/.sbin`** (`pkgsrc-audit.sh`) |
| 上流 pkgsrc への当て物 | **[pkgsrc-zakinko](https://github.com/zakinko/pkgsrc-zakinko) の `overlay/`**。CI が clone して当てる |
| 上流へ送る diff とメール | ここ (`doc/upstream/`) |
| ソースから建てる | **`~/.sbin`** (`pkgsrc-bootstrap.sh`) |
| 外でバイナリを作る | ここ |
| `pkgin` のリポジトリ設定と更新 | ここ (`bin/nb-update`) |

`pkg_summary` はどちらも作る。向こうの `pkgsrc-build-pkg-summary.sh` は
`.gz`、こちらは `.xz`。**pkgin は `.xz` → `.bz2` → `.gz` の順に探す**ので、
同じディレクトリに両方あると `.gz` の方が黙って無視される。混ぜないこと。

## 気をつけるところ

- **`/dev/kvm`**: GitHub の hosted runner で使えるかは時期とプランで揺れる。
  無いと TCG になって 10 倍以上遅くなり、実質完走しない。ワークフローは
  警告を出すので、Actions のログの頭を見ること。
- **資産名**: GitHub は Releases の資産名の `[A-Za-z0-9._-]` 以外を `.` に
  潰す。`gtk+` のような `+` を含むパッケージを入れると、pkgin が組み立てる
  URL と一致しなくなる。ワークフローは公開前に名前を検査して落とす。
  当たったら配布を GitHub Pages に移すか、その一つだけ別扱いにする。
- **6 時間**: `BUILD_DEADLINE_MIN` (既定 260 分) でゲストが自分から降りる。
  runner の上限は 360 分なので、持ち帰りと公開の時間を残してある。
- **リリースの容量**: 資産一つあたり 2GB まで。パッケージ単体でこれを超える
  ことはまず無い。

## anita で踏んだ穴

手元で回して見つけたもの。どれも黙って落ちるので、同じところで悩まないよう
に書き残しておく。

| 症状 | 原因 | 対処 |
|---|---|---|
| `anita` が引数を受け付けない / ポルトガル語のヘルプが出る | **PyPI の `anita` は同名の別物**（論理学のツール）。本家は PyPI にいない | `pip install pexpect https://www.gson.org/netbsd/anita/download/anita-2.18.tar.gz` |
| `RuntimeError: could not run mkisofs` | anita は install 用 ISO を焼く。その道具が無い | Linux は `genisoimage`、macOS は `brew install cdrtools` |
| `--run` の中で `Can't assign requested address` | **anita は NIC を明示的に足さない**（`anita.py` の該当行がコメントアウト）。qemu の既定 NIC はぶら下がるが、入れたばかりのシステムでは `dhcpcd` が動いていない | `--run` の先頭で `dhcpcd -w` |
| macOS で作った tarball の展開が失敗扱いになる | 全ファイルに `com.apple.provenance` が付き、NetBSD の tar が一件ごとに文句を言った上に非ゼロ終了する | 作る側で `--no-xattrs`、展開側は終了ステータスではなく中身で判定 |

anita 2.18 自身のバグも一つ。`make_iso()` の Darwin と FreeBSD の判定が
`sysname[0] == 'Darwin'`（文字列の先頭一文字との比較なので常に偽）になって
いて、macOS でも `hdiutil` の経路に入らない。mkisofs を入れれば動くので
迂回してある。

## 出典

- [anita — Automated NetBSD Installation and Test Application](https://www.gson.org/netbsd/anita/)
- [pkgsrc](https://github.com/NetBSD/pkgsrc)
- 自作パッケージ: [pkgsrc-zakinko](https://github.com/zakinko/pkgsrc-zakinko)
  (FreeBSD 版は [ports-zakinko](https://github.com/zakinko/ports-zakinko))
