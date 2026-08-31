#!/bin/sh
# mozc の ipc を他の BSD へ広げるのに要る事実を、その OS の上で測る。
#
# #ifdef が在ることは、構造体が pid を持つことも MIB の並びが合っていることも
# 意味しない。だから当てずに走らせる。落ちた場合も答えの一つとして出す。
set -u
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT INT TERM HUP
CC=${CC:-cc}

echo "########## $(uname -srm) ##########"
$CC --version 2>&1 | head -1

say() { printf '%-38s %s\n' "$1" "$2"; }

# --- 1. 型が在るか。参照して初めて分かるものは、通るかどうかで測る -----------
try() {                 # try <名前> <本体>
  cat > "$T/t.c" <<EOF
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/sysctl.h>
#include <sys/param.h>
#include <unistd.h>
int main(void){ $2 ; return 0; }
EOF
  if $CC -o "$T/t" "$T/t.c" >"$T/err" 2>&1; then say "$1" "通る"
  else say "$1" "通らない"; fi
}

echo
echo '=== 型と欄 (参照が通るかで測る) ==='
try 'struct ucred に pid'        'struct ucred c; (void)c.pid;'
try 'struct sockpeercred に pid' 'struct sockpeercred c; (void)c.pid;'
try 'struct unpcbid に unp_pid'  'struct unpcbid c; (void)c.unp_pid;'
try 'struct xucred'              'struct xucred c; (void)c.cr_uid;'
try 'struct xucred に cr_pid'    'struct xucred c; (void)c.cr_pid;'
try 'getpeereid(2)'              'uid_t u; gid_t g; (void)getpeereid(0,&u,&g);'

# --- 2. 定数 ----------------------------------------------------------------
cat > "$T/c.c" <<'EOF'
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/sysctl.h>
#include <stddef.h>
#include <stdio.h>
int main(void){
  printf("  sockaddr_un=%zu offsetof(sun_path)=%zu sun_path=%zu\n",
         sizeof(struct sockaddr_un), offsetof(struct sockaddr_un, sun_path),
         sizeof(((struct sockaddr_un*)0)->sun_path));
#ifdef SO_PEERCRED
  printf("  SO_PEERCRED=%d\n", SO_PEERCRED);
#else
  printf("  SO_PEERCRED 無し\n");
#endif
#ifdef LOCAL_PEERCRED
  printf("  LOCAL_PEERCRED=%d\n", LOCAL_PEERCRED);
#else
  printf("  LOCAL_PEERCRED 無し\n");
#endif
#ifdef LOCAL_PEEREID
  printf("  LOCAL_PEEREID=%d\n", LOCAL_PEEREID);
#else
  printf("  LOCAL_PEEREID 無し\n");
#endif
#ifdef KERN_PROC_PATHNAME
  printf("  KERN_PROC_PATHNAME=%d\n", KERN_PROC_PATHNAME);
#else
  printf("  KERN_PROC_PATHNAME 無し\n");
#endif
#ifdef KERN_PROC_ARGS
  printf("  KERN_PROC_ARGS=%d\n", KERN_PROC_ARGS);
#endif
#ifdef KERN_PROC
  printf("  KERN_PROC=%d\n", KERN_PROC);
#endif
#ifdef XUCRED_VERSION
  printf("  XUCRED_VERSION=%d\n", XUCRED_VERSION);
#else
  printf("  XUCRED_VERSION 無し\n");
#endif
  printf("  sizeof(sun_family)=%zu\n",
         sizeof(((struct sockaddr_un*)0)->sun_family));
  return 0;
}
EOF
echo
echo '=== 大きさと定数 ==='
$CC -o "$T/c" "$T/c.c" >"$T/err" 2>&1 && "$T/c" || { echo "  組めない:"; head -5 "$T/err"; }

# --- 3. 本当に走らせる。実 socket を繋いで peer の身元を取る ----------------
cat > "$T/r.c" <<'EOF'
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/sysctl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
  char path[128];
  snprintf(path, sizeof(path), "/tmp/.probe.%u", (unsigned)getpid());
  unlink(path);

  int ls = socket(AF_UNIX, SOCK_STREAM, 0);
  struct sockaddr_un a; memset(&a, 0, sizeof(a));
  a.sun_family = AF_UNIX;
  snprintf(a.sun_path, sizeof(a.sun_path), "%s", path);
  size_t len = offsetof(struct sockaddr_un, sun_path) + strlen(path);
  if (bind(ls, (struct sockaddr *)&a, len) != 0) {
    printf("  bind(len=%zu) 失敗: %s\n", len, strerror(errno)); return 1;
  }
  printf("  bind(len=%zu) 成功。頼んだ名前で出来たか: %s\n", len,
         access(path, F_OK) == 0 ? "はい" : "いいえ (切れている)");
  listen(ls, 1);

  int cs = socket(AF_UNIX, SOCK_STREAM, 0);
  if (connect(cs, (struct sockaddr *)&a, len) != 0) {
    printf("  connect 失敗: %s\n", strerror(errno)); unlink(path); return 1;
  }
  int as = accept(ls, NULL, NULL);
  printf("  connect/accept 成功\n");

  pid_t peer = 0;
#if defined(LOCAL_PEEREID)
  { struct unpcbid c; socklen_t n = sizeof(c);
    if (getsockopt(as, 0, LOCAL_PEEREID, &c, &n) == 0) {
      peer = c.unp_pid;
      printf("  LOCAL_PEEREID   pid=%d uid=%d\n", (int)c.unp_pid, (int)c.unp_euid);
    } else printf("  LOCAL_PEEREID   失敗: %s\n", strerror(errno)); }
#endif
#if defined(SO_PEERCRED)
  {
#if defined(__OpenBSD__)
    struct sockpeercred c;
#else
    struct ucred c;
#endif
    socklen_t n = sizeof(c);
    if (getsockopt(as, SOL_SOCKET, SO_PEERCRED, &c, &n) == 0) {
      peer = c.pid;
      printf("  SO_PEERCRED     pid=%d uid=%d\n", (int)c.pid, (int)c.uid);
    } else printf("  SO_PEERCRED     失敗: %s\n", strerror(errno)); }
#endif
#if defined(LOCAL_PEERCRED)
  { struct xucred c; socklen_t n = sizeof(c);
    if (getsockopt(as, 0, LOCAL_PEERCRED, &c, &n) == 0) {
      printf("  LOCAL_PEERCRED  uid=%d ngroups=%d\n", (int)c.cr_uid, (int)c.cr_ngroups);
#if defined(XUCRED_VERSION)
      printf("                  version=%u\n", (unsigned)c.cr_version);
#endif
    } else printf("  LOCAL_PEERCRED  失敗: %s\n", strerror(errno)); }
#endif
  { uid_t u = 0; gid_t g = 0;
    if (getpeereid(as, &u, &g) == 0)
      printf("  getpeereid     uid=%d gid=%d (pid は返さない)\n", (int)u, (int)g);
    else printf("  getpeereid     失敗: %s\n", strerror(errno)); }
  printf("  → peer の pid は %s\n", peer ? "取れる" : "取れない");

  /* 実行パスを sysctl で引く。並びが OS ごとに違うので両方試す */
  if (peer == 0) peer = getpid();
#if defined(KERN_PROC_PATHNAME)
  {
    char buf[1024]; size_t sz;
# if defined(KERN_PROC_ARGS)
    { int mib[4] = {CTL_KERN, KERN_PROC_ARGS, (int)peer, KERN_PROC_PATHNAME};
      memset(buf, 0, sizeof(buf)); sz = sizeof(buf);
      if (sysctl(mib, 4, buf, &sz, NULL, 0) == 0)
        printf("  {KERN_PROC_ARGS, pid, PATHNAME} -> %zu byte [%s]\n", sz, buf);
      else
        printf("  {KERN_PROC_ARGS, pid, PATHNAME} -> 失敗: %s\n", strerror(errno)); }
# endif
# if defined(KERN_PROC)
    { int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, (int)peer};
      memset(buf, 0, sizeof(buf)); sz = sizeof(buf);
      if (sysctl(mib, 4, buf, &sz, NULL, 0) == 0)
        printf("  {KERN_PROC, PATHNAME, pid} -> %zu byte [%s]\n", sz, buf);
      else
        printf("  {KERN_PROC, PATHNAME, pid} -> 失敗: %s\n", strerror(errno)); }
# endif
  }
#else
  printf("  KERN_PROC_PATHNAME が無いので実行パスは引けない\n");
#endif
  close(as); close(cs); close(ls); unlink(path);
  return 0;
}
EOF
echo
echo '=== 実際に繋いで取る ==='
if $CC -o "$T/r" "$T/r.c" >"$T/err" 2>&1; then "$T/r"; else echo "  組めない:"; head -20 "$T/err"; fi
echo
echo "########## ここまで $(uname -s) ##########"
