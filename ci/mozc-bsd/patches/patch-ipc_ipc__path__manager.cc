$NetBSD: patch-ipc_ipc__path__manager.cc,v 1.7 2024/02/10 01:17:28 ryoon Exp $

Look up the server's path on the BSDs, where /proc is not what Linux has.

The Linux arm of IsValidServer reads /proc/<pid>/exe.  On NetBSD procfs is
not a required mount -- the fstab that ships inside the boot images carries
it with noauto -- and the other three BSDs have no such file at all, so the
readlink fails.  kern.proc.<pid>.pathname depends on no mount, and the
__APPLE__ arm above already reads process information with sysctl.

The MIB is not the same shape everywhere.  Measured, by asking each kernel
on the machine itself:

  NetBSD     {CTL_KERN, KERN_PROC_ARGS, pid, KERN_PROC_PATHNAME}
  FreeBSD    {CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, pid}
  DragonFly  {CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, pid}
  OpenBSD    no KERN_PROC_PATHNAME at all

Passing the other order does not report an error the caller can see: on
NetBSD the FreeBSD order returns 0 and writes nothing, so a length of zero
has to be treated as failure rather than as an empty path.

KERN_PROC_PATHNAME is 5 on NetBSD, 12 on FreeBSD and 9 on DragonFly, so the
two arms that share a shape still cannot share a number.

OpenBSD has no way to ask for another process's executable, so the
comparison this function exists for cannot be made there.  It returns true
with nothing cached rather than falling through: server_path_ is cleared
before these arms, so falling through would measure a real path against an
empty string and refuse a server that is fine.  Caching the expected path
instead would balance the books while claiming a lookup that never happened.
What is left on OpenBSD is the uid check in IsPeerValid.

On DragonFly this arm is correct but is not reached: struct xucred has no
cr_pid there, so IsPeerValid leaves *pid at zero and IsValidServer returns
at its first statement.  Keeping DragonFly in the branch means that if the
field ever appears, the check starts working rather than falling through to
the comparison with an empty server_path_.

--- ipc/ipc_path_manager.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ ipc/ipc_path_manager.cc
@@ -67,6 +67,12 @@
 #include "base/mac/mac_util.h"
 #endif  // __APPLE__
 
+#if defined(__NetBSD__) || defined(__FreeBSD__) || defined(__DragonFly__) || \
+    defined(__OpenBSD__)
+#include <sys/param.h>
+#include <sys/sysctl.h>
+#endif  // BSD
+
 #ifdef _WIN32
 // clang-format off
 #include <windows.h>
@@ -389,6 +395,54 @@
   server_pid_ = pid;
 #endif  // __APPLE__
 
+#if defined(__NetBSD__) || defined(__FreeBSD__) || defined(__DragonFly__)
+  // Do not read /proc/<pid>/exe here.  procfs is not a required mount on
+  // NetBSD -- the fstab that ships inside the NetBSD boot images carries it
+  // with noauto -- and the other two have no such file.  kern.proc.<pid>
+  // .pathname depends on no mount, and the __APPLE__ branch above already
+  // reads process information with sysctl.
+#if defined(__NetBSD__)
+  int name[] = {CTL_KERN, KERN_PROC_ARGS, static_cast<int>(pid),
+                KERN_PROC_PATHNAME};
+#else
+  // FreeBSD and DragonFly hang the same lookup off KERN_PROC instead, with
+  // the pid last.  The constant differs as well -- 12 and 9 against NetBSD's
+  // 5 -- so it is named rather than written out.
+  int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME,
+                static_cast<int>(pid)};
+#endif  // __NetBSD__
+  char path[MAXPATHLEN];
+  size_t path_len = sizeof(path);
+  if (sysctl(name, std::size(name), path, &path_len, nullptr, 0) < 0) {
+    LOG(ERROR) << "sysctl KERN_PROC_PATHNAME failed: " << strerror(errno);
+    return false;
+  }
+  if (path_len == 0) {
+    // A MIB the kernel accepts but has no answer for returns 0 and writes
+    // nothing.  Giving the other order does exactly that, so a return of 0
+    // is not by itself evidence of a path.
+    LOG(ERROR) << "sysctl KERN_PROC_PATHNAME returned no path";
+    return false;
+  }
+
+  server_path_ = path;
+  server_pid_ = pid;
+#endif  // __NetBSD__ || __FreeBSD__ || __DragonFly__
+
+#if defined(__OpenBSD__)
+  // OpenBSD has no KERN_PROC_PATHNAME, and no other interface that names
+  // another process's executable, so the comparison below cannot be made.
+  // Return here rather than falling through: server_path_ was cleared above,
+  // so falling through would compare the expected path against an empty
+  // string, fail, and refuse a server that is fine.
+  //
+  // The peer's uid was checked in IsPeerValid, and the socket sits in the
+  // user's own directory with mode 0600.  That is the boundary that holds
+  // here.  Comparing the binary is a layer on top of it, and this platform
+  // offers no means to add it.
+  return true;
+#endif  // __OpenBSD__
+
 #ifdef __linux__
   // load from /proc/<pid>/exe
   std::string proc = absl::StrFormat("/proc/%u/exe", pid);
