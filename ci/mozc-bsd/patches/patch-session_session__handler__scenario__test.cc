$NetBSD: patch-session_session__handler__scenario__test.cc,v 1.1 2024/02/10 01:17:28 ryoon Exp $

Widen a negated Linux condition to the BSDs.

As in gui/dictionary_tool: the test excludes Linux, so the BSDs are added
with && !defined(...) rather than with ||.

--- session/session_handler_scenario_test.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ session/session_handler_scenario_test.cc
@@ -172,7 +172,9 @@
     DATA_DIR "select_minor_prediction.txt",
     DATA_DIR "select_prediction.txt",
     DATA_DIR "select_t13n_by_key.txt",
-#ifndef __linux__
+#if !defined(__linux__) && !defined(__NetBSD__) && \
+    !defined(__FreeBSD__) && !defined(__OpenBSD__) && \
+    !defined(__DragonFly__)
     // This test requires cascading window.
     // TODO(hsumita): Removes this ifndef block.
     DATA_DIR "select_t13n_on_cascading_window.txt",
