$NetBSD: patch-base_cpu__stats.cc,v 1.5 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- base/cpu_stats.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ base/cpu_stats.cc
@@ -116,7 +116,8 @@
 
 #endif  // __APPLE__
 
-#if defined(__linux__) || defined(__wasm__)
+#if defined(__linux__) || defined(__wasm__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
   // NOT IMPLEMENTED
   // TODO(taku): implement Linux version
   // can take the info from /proc/stats
@@ -169,7 +170,8 @@
                              TimeValueTToInt64(task_times_info.system_time);
 #endif  // __APPLE__
 
-#if defined(__linux__) || defined(__wasm__)
+#if defined(__linux__) || defined(__wasm__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
   // not implemented
   const uint64_t total_times = 0;
   const uint64_t cpu_times = 0;
@@ -200,7 +202,8 @@
   return static_cast<size_t>(basic_info.avail_cpus);
 #endif  // __APPLE__
 
-#if defined(__linux__) || defined(__wasm__)
+#if defined(__linux__) || defined(__wasm__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
   // Not implemented
   return 1;
 #endif  // __linux__ || __wasm__
