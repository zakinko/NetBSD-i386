$NetBSD: patch-config_stats__config__util__test.cc,v 1.5 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- config/stats_config_util_test.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ config/stats_config_util_test.cc
@@ -688,7 +688,8 @@
   EXPECT_FALSE(StatsConfigUtil::IsEnabled());
 #endif  // CHANNEL_DEV
 }
-#elif defined(__linux__)  // __ANDROID__
+#elif defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)  // __ANDROID__
 TEST(StatsConfigUtilTestLinux, DefaultValueTest) {
   EXPECT_FALSE(StatsConfigUtil::IsEnabled());
 }
