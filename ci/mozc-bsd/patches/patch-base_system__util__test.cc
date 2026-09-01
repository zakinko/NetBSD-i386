$NetBSD: patch-base_system__util__test.cc,v 1.1 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- base/system_util_test.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ base/system_util_test.cc
@@ -59,7 +59,8 @@
 #elif defined(__APPLE__)
   // TODO(komatsu): write a test.
 
-#elif defined(__linux__)
+#elif defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   EnvironMock environ_mock;
   FileUtilMock file_util_mock;
   SystemUtil::SetUserProfileDirectory("");
