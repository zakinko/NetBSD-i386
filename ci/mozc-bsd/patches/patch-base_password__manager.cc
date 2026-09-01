$NetBSD: patch-base_password__manager.cc,v 1.6 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- base/password_manager.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ base/password_manager.cc
@@ -265,7 +265,8 @@
 // We use plain text file for password storage on Linux. If you port this module
 // to other Linux distro, you might want to implement a new password manager
 // which adopts some secure mechanism such like gnome-keyring.
-#if defined(__linux__) || defined(__wasm__)
+#if defined(__linux__) || defined(__wasm__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
 typedef PlainPasswordManager DefaultPasswordManager;
 #endif  // __linux__ || __wasm__
 
