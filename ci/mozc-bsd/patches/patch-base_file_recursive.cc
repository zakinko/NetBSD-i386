$NetBSD: patch-base_file_recursive.cc,v 1.1 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- base/file/recursive.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ base/file/recursive.cc
@@ -105,7 +105,9 @@
 }  // namespace
 
 #if (defined(__linux__) && !defined(__ANDROID__)) || \
-    (defined(TARGET_OS_OSX) && TARGET_OS_OSX)
+    (defined(TARGET_OS_OSX) && TARGET_OS_OSX) || \
+    defined(__NetBSD__) || defined(__FreeBSD__) || defined(__OpenBSD__) || \
+    defined(__DragonFly__)
 
 absl::Status DeleteRecursively(const zstring_view path) {
   // fts is not POSIX, but it's available on both Linux and MacOS.
