$NetBSD: patch-client_client.cc,v 1.5 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- client/client.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ client/client.cc
@@ -897,7 +897,8 @@
     return false;
   }
 
-#if defined(_WIN32) || defined(__linux__)
+#if defined(_WIN32) || defined(__linux__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
   std::string arg = absl::StrCat("--mode=", mode);
   if (!extra_arg.empty()) {
     absl::StrAppend(&arg, " ", extra_arg);
