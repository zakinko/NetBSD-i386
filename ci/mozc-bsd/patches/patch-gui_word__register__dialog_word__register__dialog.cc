$NetBSD: patch-gui_word__register__dialog_word__register__dialog.cc,v 1.7 2024/02/10 01:17:28 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- gui/word_register_dialog/word_register_dialog.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ gui/word_register_dialog/word_register_dialog.cc
@@ -100,7 +100,8 @@
   }
   return QLatin1String("");
 #endif  // _WIN32
-#if defined(__APPLE__) || defined(__linux__)
+#if defined(__APPLE__) || defined(__linux__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
   return QString::fromUtf8(::getenv(envname));
 #endif  // __APPLE__ or __linux__
   // TODO(team): Support other platforms.
