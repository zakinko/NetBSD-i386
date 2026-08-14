# overlay

上流 pkgsrc のパッケージに、こちらで手を入れたものを置くところ。ビルド前に
pkgsrc ツリーの上へそのまま被せる。

```
overlay/<カテゴリ>/<パッケージ>/...  →  /usr/pkgsrc/<カテゴリ>/<パッケージ>/...
```

被せたあと、そのディレクトリで `make makepatchsum` が走って distinfo に
patch の SHA1 が入る。これは pkgsrc 標準のターゲットなので、こちらで
ハッシュを計算する必要はない。

## 決まりごと

- **PKGREVISION を上げる。** patch を足しただけだと PKGNAME が変わらず、
  手元の pkgin が「同じものが入っている」と判断して入れ替えてくれない。
  Makefile ごと写して番号を上げるのが手っ取り早い。
- **一時的なものとして扱う。** ここに置くのは「上流 pkgsrc がまだ取り込んで
  いない」ものだけ。取り込まれたらディレクトリごと消す。消し忘れると、
  上流が直したあとも古い写しの Makefile を使い続けることになる。
- **上流にも送る。** ここに置くのはあくまで手元をすぐ直すためで、本筋は
  pkgsrc 本体に入れること。

## 今あるもの

| | 何 | 消してよくなる条件 |
|---|---|---|
| `sysutils/augeas` | CVE-2025-2588 の NULL 参照修正 + PKGREVISION 2 | pkgsrc が同等の patch を入れるか、augeas が 1.14.2 を出して pkgsrc が追随したとき |
| `textproc/libxml2` | 2.15.1 → 2.15.3。CVE 5 件分 | pkgsrc が 2.15.2 以降に上がったとき |

どちらも上流 pkgsrc へ送る用意ができている。[doc/upstream/](../doc/upstream/)
を見ること。
