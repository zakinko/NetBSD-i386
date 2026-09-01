$NetBSD: patch-ipc_unix__ipc.cc,v 1.7 2024/02/10 01:17:28 ryoon Exp $

Build the Unix domain IPC on the BSDs as well as Linux.

The file is guarded by __linux__ alone, and mach_ipc.cc and win32_ipc.cc are
guarded by __APPLE__ and _WIN32, so on a BSD all three translation units are
empty and IPCClient and IPCServer have no definitions at all.

Each kernel reports the peer differently.  Measured by connecting a real
AF_UNIX socket on each system, with a child process on the other end so that
a returned pid could be told apart from the caller's own:

  Linux      SO_PEERCRED     struct ucred         pid
  NetBSD     LOCAL_PEEREID   struct unpcbid       unp_pid
  OpenBSD    SO_PEERCRED     struct sockpeercred  pid
  FreeBSD    LOCAL_PEERCRED  struct xucred        cr_pid
  DragonFly  LOCAL_PEERCRED  struct xucred        no pid at all

OpenBSD does have SO_PEERCRED; getpeereid(2) exists alongside it and reports
only uid and gid.  On FreeBSD cr_pid shares a union with an older unused
member, so it is read only when cr_version says the union holds it, and
DragonFly still carries that member and has no pid to read.  IsValidServer
already treats a zero pid as "cannot check which binary the peer is" and
returns true, which is what DragonFly ends up doing.

LOCAL_PEERCRED is declared in <sys/un.h>, not <sys/ucred.h>; struct xucred
needs <sys/ucred.h>, which wants <sys/param.h> ahead of it.

The length passed to connect(2) and bind(2) has to be measured from
offsetof(sun_path).  All four BSDs put sun_path at two, after a one byte
sun_len and a one byte sun_family, so sizeof(sun_family) is one short and the
last character of the socket path is dropped.  Linux has no sun_len, but its
sa_family_t is two bytes wide, so sun_path starts at two there as well and
one expression is right everywhere -- which is what both libcs mean by
SUN_LEN.

--- ipc/unix_ipc.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ ipc/unix_ipc.cc
@@ -28,7 +28,8 @@
 // OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 // __linux__ only. Note that __ANDROID__/__wasm__ don't reach here.
-#if defined(__linux__)
+#if defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
 
 #include <fcntl.h>
 #include <sys/select.h>
@@ -36,6 +37,10 @@
 #include <sys/stat.h>
 #include <sys/time.h>
 #include <sys/un.h>
+#if defined(__FreeBSD__) || defined(__DragonFly__)
+#include <sys/param.h>
+#include <sys/ucred.h>
+#endif  // __FreeBSD__ || __DragonFly__
 #include <unistd.h>
 
 #include <cerrno>
@@ -119,6 +124,7 @@
 bool IsPeerValid(int socket, pid_t *pid) {
   *pid = 0;
 
+#if defined(__linux__)
   struct ucred peer_cred;
   int peer_cred_len = sizeof(peer_cred);
   if (getsockopt(socket, SOL_SOCKET, SO_PEERCRED, &peer_cred,
@@ -133,6 +139,65 @@
   }
 
   *pid = peer_cred.pid;
+#elif defined(__NetBSD__)
+  struct unpcbid peer_cred;
+  socklen_t peer_cred_len = sizeof(peer_cred);
+  if (getsockopt(socket, 0, LOCAL_PEEREID, &peer_cred, &peer_cred_len) < 0) {
+    LOG(ERROR) << "cannot get peer credential. Not a Unix socket?";
+    return false;
+  }
+
+  if (peer_cred.unp_euid != ::geteuid()) {
+    LOG(WARNING) << "uid mismatch." << peer_cred.unp_euid
+                 << "!=" << ::geteuid();
+    return false;
+  }
+
+  *pid = peer_cred.unp_pid;
+#elif defined(__OpenBSD__)
+  struct sockpeercred peer_cred;
+  socklen_t peer_cred_len = sizeof(peer_cred);
+  if (getsockopt(socket, SOL_SOCKET, SO_PEERCRED, &peer_cred,
+                 &peer_cred_len) < 0) {
+    LOG(ERROR) << "cannot get peer credential. Not a Unix socket?";
+    return false;
+  }
+
+  if (peer_cred.uid != ::geteuid()) {
+    LOG(WARNING) << "uid mismatch." << peer_cred.uid << "!=" << ::geteuid();
+    return false;
+  }
+
+  // The pid is reported here, but nothing can be done with it: OpenBSD has
+  // no interface that names another process's executable, so IsValidServer
+  // cannot compare binaries.  It is supplied because it is true, and because
+  // leaving it zero would say "no credentials" rather than "no lookup".
+  *pid = peer_cred.pid;
+#elif defined(__FreeBSD__) || defined(__DragonFly__)
+  struct xucred peer_cred;
+  socklen_t peer_cred_len = sizeof(peer_cred);
+  if (getsockopt(socket, 0, LOCAL_PEERCRED, &peer_cred, &peer_cred_len) < 0) {
+    LOG(ERROR) << "cannot get peer credential. Not a Unix socket?";
+    return false;
+  }
+
+  if (peer_cred.cr_uid != ::geteuid()) {
+    LOG(WARNING) << "uid mismatch." << peer_cred.cr_uid << "!=" << ::geteuid();
+    return false;
+  }
+
+#if defined(__FreeBSD__)
+  // cr_pid shares a union with an older unused member, and is the live half
+  // when cr_version is XUCRED_VERSION.
+  if (peer_cred.cr_version == XUCRED_VERSION) {
+    *pid = peer_cred.cr_pid;
+  }
+#else
+  // DragonFly still carries the unused member, so there is no pid to read.
+  // *pid stays zero, and IsValidServer returns at its first statement; the
+  // uid comparison above is what holds there.
+#endif  // __FreeBSD__
+#endif  // __linux__
 
   return true;
 }
@@ -263,7 +328,9 @@
     address.sun_family = AF_UNIX;
     absl::SNPrintF(address.sun_path, sizeof(address.sun_path), "%s",
                    server_address);
-    const size_t sun_len = sizeof(address.sun_family) + server_address_length;
+    // sun_path does not start at sizeof(sun_family) on the BSDs (sun_len).
+    const size_t sun_len =
+        offsetof(struct sockaddr_un, sun_path) + server_address_length;
     pid_t pid = 0;
     if (::connect(socket_, reinterpret_cast<const sockaddr *>(&address),
                   sun_len) != 0 ||
@@ -376,7 +443,9 @@
   int on = 1;
   ::setsockopt(socket_, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<char *>(&on),
                sizeof(on));
-  const size_t sun_len = sizeof(addr.sun_family) + server_address_.size();
+  // sun_path does not start at sizeof(sun_family) on the BSDs (sun_len).
+  const size_t sun_len =
+      offsetof(struct sockaddr_un, sun_path) + server_address_.size();
   if (is_file_socket) {
     // Linux does not use files for IPC.
     ::chmod(server_address_.c_str(), 0600);
