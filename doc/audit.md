# audit-packages に出ているものの棚卸し

2026-08-14 時点。`pkg_admin audit` が出した 21 件を、上流が直したのか、直せる
状態にないのか、そもそも直る見込みがないのかで仕分けたもの。

pkgsrc 側の状態は **CVS HEAD で確認済み** (GitHub のミラーではなく)。送る
用意ができているものは [doc/upstream/](upstream/) にある。

## 先に、読み方

`pkg-vulnerabilities` の各行の左端が効いている。

| 書き方 | 意味 |
|---|---|
| `libxml2<2.14.5` | 2.14.5 で直る。上げれば消える。 |
| `libxml2-[0-9]*` | **全バージョンが該当**。pkgsrc が「直った版はまだ無い」と言っている。 |

今回残っている 21 件は、perl の 1 件を含めて**全部が後者**。ただし後者は
「pkgsrc がそう書いた時点の話」でしかなく、**その後上流が直しても、誰かが
エントリを絞らない限りずっと出続ける**。実際 ncurses と libxml2 がこれに
当たっていた。以下、上流の実際の状態で仕分ける。

## 一覧

| パッケージ | 件数 | 上流の実際 | どこを直すか |
|---|---|---|---|
| ncurses 6.6 | 1 | **6.6 に修正が入っている** | pkgsrc のエントリ。誤検知 |
| libxml2 2.15.1 | 6 | **5 件は 2.15.2 で修正済み。開発も再開** | pkgsrc の版上げ (2.15.1 → 2.15.3) |
| augeas 1.14.1 | 1 | master に修正あり・未リリース | pkgsrc に patch。**この repo に入れた** |
| emacs26-nox11 | 2 | 26 系は 2019 で終了 | `EMACS_TYPE` を `emacs30nox` に |
| lua53 | eol | Lua 5.3 サポート終了 | lua54 / lua55 へ |
| expat 2.8.2 | 1 | 健在だが本件だけ未修正 | 待ち |
| python313 3.13.15 | 8 | 健在。未リリース | 待ち |
| perl 5.44.0 | 1 | 15 年開いたまま。issue は生きている | File::Temp 本体。手伝える |

---

## ncurses 6.6 / CVE-2025-69720 — pkgsrc のエントリが古いだけ

`infocmp` の `analyze_string()` で `buf2` (4096 バイト) に長さを見ずにコピー
していたスタックオーバーフロー。

上流は ncurses 6.5 の 20251213 パッチで修正し、**6.6 は 2025-12-30 リリース
なのでこれを含んでいる**。実際に 6.6 の tarball を開いて確認した。
`progs/infocmp.c` は rev 1.177 (2025-12-27) で、`analyze_string()` に

```c
if ((len = strlen(cp)) > MAX_TERMINFO_LENGTH)
    len = MAX_TERMINFO_LENGTH;
```

と `(len < sizeof(buf3))` のガードが入っている。**今入っている 6.6 は直って
いる。**

### どこを直すか

pkgsrc の `pkg-vulnerabilities` の

```
ncurses-[0-9]*	buffer-overflow	https://nvd.nist.gov/vuln/detail/CVE-2025-69720
```

を `ncurses<6.6` に絞ってもらう。宛先は **pkgsrc-security@NetBSD.org**。
文面は [doc/upstream/pkg-vulnerabilities.mail](upstream/pkg-vulnerabilities.mail)
に libxml2 の分と一緒に書いてある。

それまでは `/usr/pkg/etc/pkg_install.conf` に

```
IGNORE_URL=https://nvd.nist.gov/vuln/detail/CVE-2025-69720
```

## libxml2 2.15.1 / 6 件 — 話が変わった

CVE-2025-8732, CVE-2025-12863, CVE-2026-0989, CVE-2026-0990, CVE-2026-0992,
CVE-2026-1757。

### 経緯

1. 2025 年 6 月、維持者 Nick Wellnhofer が「無給のボランティアが週に数時間も
   脆弱性の切り分けに使うのは持続しない」として、セキュリティ embargo を
   一切受け付けないと宣言。
2. 2025 年 9 月、維持者を降りた。GitLab には現在も
   "This project is unmaintained and has known security issues" の掲示がある。
3. **その後、別の人たちが続きを出している。** 2.15.2 (2026-03-03) と
   2.15.3 (2026-04-15) がリリース済みで、コミット数の筆頭は Daniel Garcia
   Moreno (GNOME 側)。2.15.2 の NEWS には新規コントリビュータが 15 人並ぶ。

掲示は残っているが、実態としては**引き継がれて動いている**。

### 2.15.2 の NEWS (Security) の中身

```
- CVE-2026-1757 fix: Memory leak in xmllint Shell - shell.c
- CVE-2026-0990 fix: Prevent infinite recursion in xmlCatalogListXMLResolve
- CVE-2026-0992 fix: Exponential behavior when handling
- CVE-2026-0989 fix: Add RelaxNG include limit
- catalog: fix stack overflow from self-referencing SGML CATALOG entries
```

最後の行が CVE-2025-8732 (`xmlParseSGMLCatalog` の無制限再帰)。つまり
**6 件中 5 件が 2.15.2 で直っている**。

残る CVE-2025-12863 (`xmlSetTreeDoc` が名前空間ポインタを更新しないことに
よる use-after-free) は 2.15.2 / 2.15.3 の NEWS に名指しが無く、直ったか
どうか確認できていない。

### どこを直すか

pkgsrc の `textproc/libxml2` が **2.15.1 のまま**(CVS HEAD で
`Makefile.common` rev 1.31, 2026-02-19 を確認)。上流最新は 2.15.3
(2026-04-15)。**pkgsrc が 4 か月遅れているだけ**。

pkgsrc がこの package に持っている patch は `patch-configure` の一本だけで、
それが 2.15.3 にそのまま当たることを確認した。つまり版上げは
`DISTNAME` と `distinfo` だけの話。

- 手元向け: [overlay/textproc/libxml2](../overlay/textproc/libxml2/) に入れた。
  次の CI で 2.15.3 になる。
- 上流向け: [doc/upstream/libxml2.diff](upstream/libxml2.diff) と
  [libxml2.mail](upstream/libxml2.mail)。宛先は pkgsrc-users@NetBSD.org
  (この package の MAINTAINER)。
- 併せて **pkg-vulnerabilities の 5 件を `libxml2<2.15.2` に絞る**よう
  pkgsrc-security@NetBSD.org へ →
  [pkg-vulnerabilities.mail](upstream/pkg-vulnerabilities.mail)。
  版を上げてもこれをやらないと audit は消えない。

`textproc/py-libxml2` も同じ Makefile.common を読むので一緒に上がる。

なお **libxml2 を引いているのは `sysutils/augeas`** (Makefile が
`textproc/libxml2/buildlink3.mk` を include している)。そこから
`py313-augeas` → `py313-certbot-apache` と繋がる。certbot の apache プラグイン
をやめて webroot か standalone に寄せられるなら、augeas ごと落とせて
libxml2 も消える。

## augeas 1.14.1 / CVE-2025-2588 — 直す場所が分かったので入れた

`src/fa.c` の `parse_regexp()` は、失敗しても `parse->error` に理由を書かずに
NULL を返すことがある。呼び出し側の `fa_expand_nocase()`,
`fa_restrict_alphabet()`, `fa_expand_char_ranges()` は `parse->error` しか
見ずに戻り値を使うので、NULL を踏む。

上流は各呼び出し側に NULL チェックを足すのではなく、`parse_regexp()` の
`error:` ラベルで理由を埋める形で直した。3 か所まとめて塞がるのでこちらが
正しい。ただし**その commit は master にあるだけで、リリースは 1.14.1 (2023)
が最後**。Fedora は git スナップショット (1.14.2-0.4.20250324git4dffa3d) を、
Debian / SUSE / Mageia は独自パッチを出荷している。

### どこを直すか

**[overlay/sysutils/augeas/patches/patch-src_fa.c](../overlay/sysutils/augeas/patches/patch-src_fa.c) に入れてある。**
CI がビルド前に pkgsrc へ被せる。手元では次の更新で `augeas-1.14.1nb2` として
入れ替わる。

```c
 error:
+    if (re == NULL && parse->error == REG_NOERROR)
+        parse->error = REG_BADPAT;
     re_unref(re);
     return NULL;
```

上流は `_REG_ENOSYS` を使っているが、これは glibc の拡張で NetBSD の
`<regex.h>` には無い。`REG_BADPAT` は POSIX で、呼び出し側に伝わる意味も
同じ。1.14.1 の `src/fa.c` に当ててコンパイル前の適用は確認済み。

CVS HEAD (`Makefile` rev 1.20) に `patches/` が無いことは確認済み。本筋は
pkgsrc 本体に入れてもらうことで、送るものは
[doc/upstream/augeas.diff](upstream/augeas.diff) と
[augeas.mail](upstream/augeas.mail) に用意した。`sysutils/augeas` の
MAINTAINER は bsiegert@NetBSD.org。取り込まれたら
`overlay/sysutils/augeas` は消す。

## emacs26-nox11 / CVE-2022-45939, CVE-2024-39331 — 設定一行

- CVE-2022-45939: `etags` 経由の任意コマンド実行
- CVE-2024-39331: org-mode 経由

`emacs26-nox11-[0-9]*` と `emacs26-[0-9]*` が挙がっていて、26 系に修正版は
無い。Emacs 26 は 2019 年で終わっている。**上流が直せないのではなく、直す
対象から外れている**。28.2 と 29.4 でそれぞれ修正済み。

pkgsrc には emacs30 があり、`emacs30<30.1` しか挙がっていない。
[mk.conf](../mk.conf) の

```
EMACS_TYPE=emacs26nox
```

を `emacs30nox` にすれば消える。**今回、設定を変えるだけで確実に消えるのは
ここだけ。**

### 巻き込まれるもの

`devel/apel` と `graphics/artist` は `EMACS_PKGNAME_PREFIX` を使う
EMACS_TYPE 依存のパッケージなので、一緒に作り直しになる。入っているのは
この二つだけのはず。確認は

```sh
pkg_info -R emacs26-nox11
```

`ng` は Emacs クローンの別ソフトで無関係。`lv` も無関係。

## lua53 — eol

Lua 5.3 は上流のサポートが終わっている。pkgsrc には lua54 と lua55 がある。

入っているパッケージの一覧を見た限り、lua を引きそうなものが無い。手で入れた
まま残っている可能性が高い。

```sh
pkg_info -R lua53
```

これが空なら `pkg_delete lua53` して `pkglist` から消すだけ。何かが引いて
いるなら `LUA_VERSION_DEFAULT` で 5.4 に寄せる。

## expat 2.8.2 / CVE-2025-66382 — 待ち

2 MiB ほどの細工した XML で数十秒 CPU を持っていかれる DoS。CVSS 2.9。

上流 issue [libexpat#1076](https://github.com/libexpat/libexpat/issues/1076)
のタイトルが "Another unfixed non-public denial-of-service vulnerability
(that affects all releases of Expat)"。報告者が詳細を NDA 下でしか出さないと
言っている状態で止まっている。Debian も stable update 送りにしている。

expat 自体は健在で、pkgsrc は既に 2.8.3 (2026-08-11)。本件は消えないが、
他の修正が乗るので上げる価値はある。次の CI で自動的に 2.8.3 になる。

## python313 3.13.15 / 8 件 — 待ち

CVE-2025-13462, CVE-2025-15366, CVE-2025-15367, CVE-2026-2297, CVE-2026-3479,
CVE-2026-3644, CVE-2026-4224 ほか。

8 件すべてが python310 から python314 まで全系列・全バージョンに対して挙げ
られている。3.13 系の最新は 3.13.15 (2026-08-05 リリース) = 今入っているもので、
その changelog にこれらの CVE は出てこない (出てくるのは CVE-2025-4330 だけ)。

**上流がまだ修正をリリースしていない。** 3.14 に上げても同じ行に当たる。
Python 本体は活発なので次のリリースで消える見込み。

## perl 5.44.0 / CVE-2011-4116 — 手伝える

`File::Temp` の `_is_safe()` がシンボリックリンクを辿ってしまう。攻撃者が
`ln -s /tmp /tmp/exploit` のように先に張っておくと、`tempdir()` を HIGH で
呼んだ被害者に攻撃者所有のパスを掴ませられる。

- [rt.cpan.org #69106](https://rt.cpan.org/Public/Bug/Display.html?id=69106) (2011)
- [Perl-Toolchain-Gang/File-Temp#14](https://github.com/Perl-Toolchain-Gang/File-Temp/issues/14) — **open**。担当者なし、PR なし、ブランチなし

### なぜ 15 年開いているか

再現手順は issue に書いてある。難しいのは直し方の方で、パス要素に symlink が
あったら弾く、という素直な実装をすると、**一時ディレクトリが正当に symlink に
なっている環境が全部壊れる**。`/tmp` が別ボリュームへの symlink になっている
構成や、macOS の `/var/folders` 系が該当する。だから「厳しくする」を既定に
できず、誰も踏み込まないまま残っている。

### 手伝うなら

1. **再現テストだけ先に送る。** `t/` に、攻撃者側の symlink を張った状態で
   `tempdir(CLEANUP => 1, DIR => ...)` を HIGH で呼ぶ失敗テストを足す PR。
   挙動を変えないので取り込まれやすく、議論の土台になる。
2. その上で**新しい安全度の追加**を提案する。既存の HIGH の意味を変えずに、
   symlink を拒む段を足す形なら後方互換が保てる。`safe_level()` の周りに
   一段足すだけなので変更は小さい。
3. File::Temp は core と CPAN の dual-life。CPAN 側 (Perl-Toolchain-Gang)
   に入って、リリースされて、perl 本体に取り込まれて、pkgsrc の perl が
   上がって、はじめて手元に届く。**そのあと pkg-vulnerabilities の
   `perl-[0-9]*` を絞ってもらう手続きも要る**。ここを忘れると直っても
   audit は消えない。

それまでは

```
IGNORE_URL=https://nvd.nist.gov/vuln/detail/CVE-2011-4116
```

---

## まとめ

| やること | 消える件数 | 手間 |
|---|---|---|
| libxml2 を 2.15.3 へ (overlay 済) + エントリを絞ってもらう | 5 | メールを送るだけ |
| `EMACS_TYPE=emacs30nox` | 2 | 一行 |
| augeas の patch (overlay 済) + pkgsrc へ送る | 1 | メールを送るだけ |
| ncurses のエントリを絞ってもらう | 1 | メールを送るだけ |
| lua53 → lua54 か削除 | eol 1 | 依存次第 |
| certbot を webroot 化 → augeas と libxml2 を落とす | (上と重複) | 設定変更 |
| python313 / expat | 9 | 上流待ち |
| perl | 1 | File::Temp に PR。長い道 |

**動かない上流を待つしかないのは python313 の 8 件と expat の 1 件だけ。**
libxml2 は「上流が死んでいるから諦める」案件ではなく、**pkgsrc が追いついて
いない**案件だった。
