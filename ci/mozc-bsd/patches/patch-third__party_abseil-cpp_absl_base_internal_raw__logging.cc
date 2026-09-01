$NetBSD$

Let raw logging work on NetBSD and DragonFly.

The list decides ABSL_HAVE_POSIX_WRITE, and with it
ABSL_LOW_LEVEL_WRITE_SUPPORTED.  Upstream names FreeBSD and OpenBSD but not
the other two, and the file does not stop when nothing matches -- the
comment above says an #error was intended, but the code only wraps the
writing half in #ifdef.  So on an unnamed platform ABSL_RAW_LOG and a failed
ABSL_RAW_CHECK compile and then print nothing at all.

Both take unistd.h and write(2) like the two already listed.  The syscall
list a few lines below is left alone: POSIX write is enough here, and going
through SYS_write would be a separate claim about each kernel.

--- third_party/abseil-cpp/absl/base/internal/raw_logging.cc.orig	2023-12-13 09:40:20.988739236 +0000
+++ third_party/abseil-cpp/absl/base/internal/raw_logging.cc
@@ -39,7 +39,8 @@
 // this, consider moving both to config.h instead.
 #if defined(__linux__) || defined(__APPLE__) || defined(__FreeBSD__) || \
     defined(__Fuchsia__) || defined(__native_client__) ||               \
-    defined(__OpenBSD__) || defined(__EMSCRIPTEN__) || defined(__ASYLO__)
+    defined(__OpenBSD__) || defined(__EMSCRIPTEN__) || defined(__ASYLO__) || \
+    defined(__NetBSD__) || defined(__DragonFly__)
 
 #include <unistd.h>
 
