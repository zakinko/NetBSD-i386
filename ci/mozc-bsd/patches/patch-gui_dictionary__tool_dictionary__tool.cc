$NetBSD: patch-gui_dictionary__tool_dictionary__tool.cc,v 1.7 2024/02/10 01:17:27 ryoon Exp $

Widen a negated Linux condition to the BSDs.

The condition excludes Linux rather than including it, so the BSDs are added
with && !defined(...) and not with ||.  Written as a list of ors it would
turn the test inside out and take the branch on every platform.

--- gui/dictionary_tool/dictionary_tool.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ gui/dictionary_tool/dictionary_tool.cc
@@ -369,7 +369,9 @@
 #endif  // !ENABLE_CLOUD_SYNC
 
   // main window
-#ifndef __linux__
+#if !defined(__linux__) && !defined(__NetBSD__) && \
+    !defined(__FreeBSD__) && !defined(__OpenBSD__) && \
+    !defined(__DragonFly__)
   // For some reason setCentralWidget crashes the dictionary_tool on Linux
   // TODO(taku): investigate the cause of the crashes
   setCentralWidget(splitter_);
