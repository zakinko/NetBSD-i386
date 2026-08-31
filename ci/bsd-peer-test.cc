/* 当てた木の ipc/unix_ipc.cc から IsPeerValid をそのまま抜いて包んだもの。
   手で写すと当て物と食い違うので抜き出しで作る。 */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#if defined(__FreeBSD__) || defined(__DragonFly__)
#include <sys/param.h>
#include <sys/ucred.h>
#endif
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

bool IsPeerValid(int socket, pid_t *pid) {
  *pid = 0;

#if defined(__linux__)
  struct ucred peer_cred;
  int peer_cred_len = sizeof(peer_cred);
  if (getsockopt(socket, SOL_SOCKET, SO_PEERCRED, &peer_cred,
                 reinterpret_cast<socklen_t *>(&peer_cred_len)) < 0) {
    fprintf(stderr, "ERROR\n");
    return false;
  }

  if (peer_cred.uid != ::geteuid()) {
    fprintf(stderr, "WARN\n");
    return false;
  }

  *pid = peer_cred.pid;
#elif defined(__NetBSD__)
  struct unpcbid peer_cred;
  socklen_t peer_cred_len = sizeof(peer_cred);
  if (getsockopt(socket, 0, LOCAL_PEEREID, &peer_cred, &peer_cred_len) < 0) {
    fprintf(stderr, "ERROR\n");
    return false;
  }

  if (peer_cred.unp_euid != ::geteuid()) {
    fprintf(stderr, "WARN\n");
    return false;
  }

  *pid = peer_cred.unp_pid;
#elif defined(__OpenBSD__)
  struct sockpeercred peer_cred;
  socklen_t peer_cred_len = sizeof(peer_cred);
  if (getsockopt(socket, SOL_SOCKET, SO_PEERCRED, &peer_cred,
                 &peer_cred_len) < 0) {
    fprintf(stderr, "ERROR\n");
    return false;
  }

  if (peer_cred.uid != ::geteuid()) {
    fprintf(stderr, "WARN\n");
    return false;
  }

  // The pid is reported here, but nothing can be done with it: OpenBSD has
  // no interface that names another process's executable, so IsValidServer
  // cannot compare binaries.  It is supplied because it is true, and because
  // leaving it zero would say "no credentials" rather than "no lookup".
  *pid = peer_cred.pid;
#elif defined(__FreeBSD__) || defined(__DragonFly__)
  struct xucred peer_cred;
  socklen_t peer_cred_len = sizeof(peer_cred);
  if (getsockopt(socket, 0, LOCAL_PEERCRED, &peer_cred, &peer_cred_len) < 0) {
    fprintf(stderr, "ERROR\n");
    return false;
  }

  if (peer_cred.cr_uid != ::geteuid()) {
    fprintf(stderr, "WARN\n");
    return false;
  }

#if defined(__FreeBSD__)
  // cr_pid shares a union with an older unused member, and is the live half
  // when cr_version is XUCRED_VERSION.
  if (peer_cred.cr_version == XUCRED_VERSION) {
    *pid = peer_cred.cr_pid;
  }
#else
  // DragonFly still carries the unused member, so there is no pid to read.
  // *pid stays zero, and IsValidServer returns at its first statement; the
  // uid comparison above is what holds there.
#endif  // __FreeBSD__
#endif  // __linux__

  return true;
}

int main(void) {
  char path[128];
  snprintf(path, sizeof(path), "/tmp/.peer.%u", (unsigned)getpid());
  unlink(path);
  int ls = socket(AF_UNIX, SOCK_STREAM, 0);
  struct sockaddr_un a; memset(&a, 0, sizeof(a));
  a.sun_family = AF_UNIX;
  snprintf(a.sun_path, sizeof(a.sun_path), "%s", path);
  /* 当て物と同じ式 */
  size_t sun_len = offsetof(struct sockaddr_un, sun_path) + strlen(path);
  if (bind(ls, (struct sockaddr *)&a, sun_len) != 0) {
    printf("bind 失敗: %s\n", strerror(errno)); return 1;
  }
  printf("bind(len=%zu) 成功、名前は %s\n", sun_len,
         access(path, F_OK) == 0 ? "切れていない" : "切れている");
  listen(ls, 1);
  pid_t kid = fork();
  if (kid == 0) {
    int c = socket(AF_UNIX, SOCK_STREAM, 0);
    if (connect(c, (struct sockaddr *)&a, sun_len) != 0) _exit(1);
    sleep(3); _exit(0);
  }
  int as = accept(ls, NULL, NULL);
  pid_t got = -1;
  bool ok = IsPeerValid(as, &got);
  printf("IsPeerValid -> %s  pid=%d  (子=%d)\n",
         ok ? "true" : "false", (int)got, (int)kid);
  if (got == 0)        printf("  → pid は 0。IsValidServer は先頭で true を返す\n");
  else if (got == kid) printf("  → 子の pid と一致\n");
  else                 printf("  ★ 子と違う pid\n");
  close(as); close(ls); unlink(path);
  int st; kill(kid, SIGTERM); waitpid(kid, &st, 0);
  return ok ? 0 : 1;
}
