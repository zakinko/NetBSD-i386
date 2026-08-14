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
  このリポジトリ                GitHub Actions                    手元の箱
  ┌────────────┐              ┌──────────────────────┐          ┌──────────┐
  │ mk.conf    │─────────────>│ ubuntu-latest        │          │ NetBSD   │
  │ pkglist    │              │  └ qemu-system-i386  │          │  i386    │
  └────────────┘              │      └ NetBSD/i386   │          │          │
                              │          make package│          │  pkgin   │
                              └──────────┬───────────┘          └────▲─────┘
                                         │ *.tgz + pkg_summary.xz    │
                                         ▼                           │
                                  ┌─────────────────┐                │
                                  │ Releases        │────────────────┘
                                  │ pkgsrc-11.0-i386│   https で取るだけ
                                  └─────────────────┘
```

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

**NetBSD 11.0/i386** を作る。リリースが変わると libc のメジャーが変わるので、
**作ったバイナリは他のリリースでは動かない**。切り替えるときは三箇所を一緒に:

| どこ | 何 |
|---|---|
| `.github/workflows/build.yml` | `NETBSD_RELEASE` と `RELEASE_TAG` |
| `bin/nb-update` | `RELEASE_TAG` |
| `ci/make-base-image.sh` | `NETBSD_RELEASE` の既定 |

### 10.1 の箱を 11.0 に上げるときの順番

順番を間違えると、上げた直後にパッケージが全部動かない箱が残る。

1. **10.1 のうちに** `bin/nb-pkglist > pkglist` して push。PKGPATH は
   リリースに依らないので、10.1 で採った一覧のまま 11.0 用が作れる。
2. CI に 11.0 用を全部作らせる。**ここまでは箱を触らない。**
3. 箱を `sysupgrade` で 11.0 に上げる。
4. `nb-update setup` してから `nb-update`。

**3 より前に `nb-update setup` を実行しないこと。** 10.1 の箱に 11.0 の
リポジトリを向けることになる。

## 初回

### 1. GitHub に置く

```sh
cd /Users/zakinko/git/NetBSD-i386
git add -A && git commit -m '最初のコミット'
gh repo create zakinko/NetBSD-i386 --public --source=. --push
```

**public であること。** `pkgin` は素の HTTP GET しかできず、認証を通せない。

### 2. まず四つだけ通す

`pkglist` には自作の四つだけ書いてある。この状態で一度 Actions を回して、
VM が立って `.tgz` がリリースに並ぶところまで確認する。ここが通れば、あとは
数の問題でしかない。

初回はベースイメージの作成 (anita で NetBSD を入れる) が入るので 30 分ほど
余分にかかる。二回目以降はキャッシュから来る。

### 3. NetBSD の箱を向ける

このリポジトリを箱にも置いて、

```sh
sudo ./bin/nb-update setup
```

これで `/usr/pkg/etc/pkgin/repositories.conf` がこのリリースを指し、
`/etc/mk.conf` がこのリポジトリの `mk.conf` になる。既存のファイルは
`.bak.<日付>` に退避される。

公式リポジトリの行は**コメントアウトされる**。混ぜると、オプションの効いて
いない方のバイナリを掴むことがあるため。

### 4. 全部に広げる

箱の上で:

```sh
./bin/nb-pkglist > pkglist
git add pkglist && git commit -m 'この箱に入っているもの全部' && git push
```

`pkglist` は PKGPATH の一覧でしかない。依存はここに書かなくても pkgsrc が
引いてきて `.tgz` にする (`ci/mk.conf.ci` の `DEPENDS_TARGET`)。

150 個を空から作ると数時間かかる。一回で終わらなければ、Actions をもう一度
回せば続きから進む。

## 普段

```sh
sudo nb-update check     # 何が上がるか見るだけ
sudo nb-update           # 更新して audit まで
sudo nb-update audit     # audit だけ
```

`nb-update` は毎週日曜 03:17 JST に CI が回った後に叩けばよい。
pkgsrc ツリーは要らないので、この箱でソースを引くことはもうない。

`/usr/pkgsrc` と `/var/tmp/pkgsrc.work` を消せる。これが本題のディスクの話。

## 中身

| ファイル | 何か |
|---|---|
| `mk.conf` | **何を作るか**を決める唯一の設定。CI と手元の両方がこれになる |
| `pkglist` | 作るパッケージの PKGPATH。`bin/nb-pkglist` が作る |
| `ci/mk.conf.ci` | CI でだけ効かせる分 (置き場所、並列度)。中身は変えない設定だけ |
| `overlay/` | 上流 pkgsrc に被せる自前の patch。[overlay/README.md](overlay/README.md) |
| `ci/make-base-image.sh` | anita で NetBSD/i386 のベースイメージを作る |
| `ci/guest-bootstrap.sh` | 入れたばかりの VM を ssh で叩ける状態にする |
| `ci/vm.sh` | ホスト側から VM を扱う小道具 |
| `ci/guest-build.sh` | VM の中で走るビルド本体 |
| `bin/nb-pkglist` | 箱に入っているものから `pkglist` を作る |
| `bin/nb-update` | 箱を更新する |
| `doc/audit.md` | `pkg_admin audit` に出ているものの棚卸し |

`mk.conf` を変えたら CI が回り、影響を受けるパッケージが作り直され、
`nb-update setup` で手元の `/etc/mk.conf` も揃う。**二つがずれると、オプションの
違うバイナリを掴むことになる。**

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
