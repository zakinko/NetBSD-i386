#!/bin/sh
# XEmacs 21.5 の look_for_coding_cookie_last_page() が buffer の終端を越えて
# 読むことを、決定的に見せる。
#
# この関数は 2025-06-02 から #if 0 で無効にされている。ChangeLog の理由は
#
#	This function appears to cause intermittent crashes (with
#	corruption of the stack) on GCC-15 with optimization.
#
# だが compiler のせいではない。memchr に渡す長さが nread のままなのに、
# 起点のポインタが前へ進むので、進んだぶんだけ終端を越える。同じ誤りが
# 二箇所ある (^L を探すループと、行を辿るループ)。
#
# 呼び出し元の buffer は UExtbyte buf[4096] でスタック上にある。書いては
# いないので何も壊れないが、読みがスタックを上へ辿る。マップされていない
# 所に届くかどうかは配置次第で、それが「断続的」の正体である。
#
# sanitizer では取り逃がす。nread が sizeof(buf) より小さいと、越えても
# 同じ配列の中に収まって何も報告されない (ASAN は無反応だった)。buffer の
# 直後に PROT_NONE のページを置けば決まる。
#
# 関数の写しはここに置かない。上流が唯一の正で、この script は checkout から
# 関数を抜き出して組む。写しを持つと、片方だけ古い状態が必ず出来る。
#
# 使い方: overread.sh <xemacs の checkout> [patch]
#   patch を渡すと当ててから同じことをする (当てた後は落ちないはず)。

set -e
SRC=$1
PATCHFILE=$2
[ -n "$SRC" ] || { echo "usage: $0 <xemacs-checkout> [patch]" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FC="$SRC/src/file-coding.c"
[ -f "$FC" ] || { echo "!! $FC が無い" >&2; exit 2; }

if [ -n "$PATCHFILE" ]; then
  echo "== patch を当てる: $PATCHFILE =="
  ( cd "$SRC" && patch -p1 -f -i "$PATCHFILE" </dev/null ) || {
    echo "!! patch が当たらなかった" >&2; exit 3; }
fi

echo "== 上流の関数を抜き出す =="
awk '
  /^static Lisp_Object$/            { pend=1; next }
  pend && /^look_for_coding_cookie_last_page \(/ {
      print "static Lisp_Object"; print; inside=1; pend=0; next }
  inside                            { print; if ($0 == "}") exit }
                                    { pend=0 }
' "$FC" > "$WORK/fn.c"
LINES=$(wc -l < "$WORK/fn.c")
echo "  $LINES 行"
[ "$LINES" -gt 50 ] || { echo "!! 抜き出しに失敗した" >&2; exit 4; }

cat > "$WORK/harness.c" <<'PRE'
/* 上流の関数をそのまま取り込み、buffer の直後に PROT_NONE のページを置く。 */
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>
#include <assert.h>
#include <sys/mman.h>
#include <unistd.h>

typedef unsigned char UExtbyte;
typedef char          Ascbyte;
typedef long          Bytecount;
typedef int           Boolint;
typedef void *        Lisp_Object;
#define Qnil          ((Lisp_Object) 0)
#define NILP(x)       ((x) == Qnil)
#define LENGTH(s)     ((Bytecount) (sizeof (s) - 1))
#define alloca_array(type, n) ((type *) alloca (sizeof (type) * (n)))
#define ascii_strncasecmp strncasecmp
#define DEBUG_DETECTION(...) do { } while (0)
static Lisp_Object
snarf_coding_system (const UExtbyte *v, Bytecount len, Boolint f)
{
  (void) v; (void) len; (void) f;
  return (Lisp_Object) 1;
}
PRE
cat "$WORK/fn.c" >> "$WORK/harness.c"
cat >> "$WORK/harness.c" <<'POST'

int
main (int argc, char **argv)
{
  long pg = sysconf (_SC_PAGESIZE);
  char *region;
  UExtbyte *buf;
  Bytecount nread, i;
  const char *mode = (argc > 1) ? argv[1] : "lastpage";

  region = mmap (NULL, pg * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
  if (region == MAP_FAILED) { perror ("mmap"); return 2; }
  if (mprotect (region + pg, pg, PROT_NONE)) { perror ("mprotect"); return 2; }
  buf = (UExtbyte *) region;
  nread = pg;
  memset (buf, 'x', nread);

  if (!strcmp (mode, "lastpage"))
    /* 改行に続かない ^L を一つ。^L を探すループが越える。 */
    buf[10] = 0x0c;
  else
    /* ^L 無し、改行を撒く。行を辿るループが越える。 */
    for (i = 40; i < nread; i += 40) buf[i] = '\n';

  printf ("%s: buffer=[%p,%p) その先は PROT_NONE\n", mode,
          (void *) buf, (void *) (buf + nread));
  fflush (stdout);
  look_for_coding_cookie_last_page (buf, nread, 1);
  printf ("%s: 越えずに戻った\n", mode);
  return 0;
}
POST

echo "== 建てる =="
cc -g -O0 -o "$WORK/harness" "$WORK/harness.c"

rc_all=0
for mode in lastpage lines; do
  "$WORK/harness" "$mode" || rc=$?; rc=${rc:-0}
  if [ "$rc" = 0 ]; then
    echo "  $mode: rc=0 (越えなかった)"
  else
    echo "  $mode: rc=$rc (フォールト = 終端を越えて読んだ)"
    rc_all=1
  fi
  unset rc
done

if [ -n "$PATCHFILE" ]; then
  [ "$rc_all" = 0 ] || { echo "!! patch を当てたのに越えている"; exit 1; }
  echo "=> patch 後: どちらも越えない"
else
  [ "$rc_all" = 1 ] || { echo "!! 素の木なのに越えなかった。想定と違う"; exit 1; }
  echo "=> 素の木: 越える (想定どおり)"
fi
