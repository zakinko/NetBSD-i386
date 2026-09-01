$NetBSD: patch-session_session.cc,v 1.7 2024/02/10 01:17:28 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- session/session.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ session/session.cc
@@ -241,7 +241,8 @@
   // Tests for session layer (session_handler_scenario_test, etc) can be
   // unstable.
 #if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || defined(__linux__) || \
-    defined(__wasm__)
+    defined(__wasm__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   context->mutable_converter()->set_use_cascading_window(false);
 #endif  // TARGET_OS_IPHONE || __linux__ || __wasm__
 }
@@ -973,7 +974,8 @@
   }
 
 #if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || defined(__linux__) || \
-    defined(__wasm__)
+    defined(__wasm__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   context_->mutable_converter()->set_use_cascading_window(false);
 #else   // TARGET_OS_IPHONE || __linux__ || __wasm__
   if (config.has_use_cascading_window()) {
