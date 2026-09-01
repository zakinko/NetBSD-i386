$NetBSD: patch-base_logging.cc,v 1.7 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs, and cast pthread_self.

pthread_self returns a pointer on the BSDs, which absl::StrCat will not take.
The Linux arm's own comment says it returns unsigned long, so the value is
cast to that.

--- base/logging.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ base/logging.cc
@@ -114,10 +114,11 @@
 #if defined(__wasm__)
   return absl::StrCat(timestamp, ::getpid(), " ",
                       static_cast<unsigned int>(pthread_self()));
-#elif defined(__linux__)
+#elif defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   return absl::StrCat(timestamp, ::getpid(), " ",
                       // It returns unsigned long.
-                      pthread_self());
+                      (unsigned long)pthread_self());
 #elif defined(__APPLE__)
 #ifdef __LP64__
   return absl::StrCat(timestamp, ::getpid(), " ",
