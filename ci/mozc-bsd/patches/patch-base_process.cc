$NetBSD: patch-base_process.cc,v 1.7 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- base/process.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ base/process.cc
@@ -98,12 +98,13 @@
       L"open", win32::Utf8ToWide(url).c_str(), nullptr);
 #endif  // _WIN32
 
-#ifdef __linux__
+#if defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
 
 #ifndef MOZC_BROWSER_COMMAND
   // xdg-open which uses kfmclient or gnome-open internally works both on KDE
   // and GNOME environments.
-#define MOZC_BROWSER_COMMAND "/usr/bin/xdg-open"
+#define MOZC_BROWSER_COMMAND "@PREFIX@/bin/xdg-open"
 #endif  // MOZC_BROWSER_COMMAND
 
   return SpawnProcess(MOZC_BROWSER_COMMAND, url);
@@ -387,7 +388,8 @@
   }
 #endif  // _WIN32
 
-#if defined(__linux__) && !defined(__ANDROID__)
+#if (defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+     defined(__OpenBSD__) || defined(__DragonFly__)) && !defined(__ANDROID__)
   constexpr char kMozcTool[] = "mozc_tool";
   const std::string arg =
       "--mode=error_message_dialog --error_type=" + error_type;
