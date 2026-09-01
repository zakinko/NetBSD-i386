$NetBSD: patch-gui_config__dialog_config__dialog.cc,v 1.8 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- gui/config_dialog/config_dialog.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ gui/config_dialog/config_dialog.cc
@@ -105,7 +105,8 @@
   setWindowTitle(tr("%1 Preferences").arg(GuiUtil::ProductName()));
 #endif  // __APPLE__
 
-#if defined(__linux__)
+#if defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   miscDefaultIMEWidget->setVisible(false);
   miscAdministrationWidget->setVisible(false);
   miscStartupWidget->setVisible(false);
@@ -115,7 +116,8 @@
   // disable logging options
   miscLoggingWidget->setVisible(false);
 
-#if defined(__linux__)
+#if defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   // The last "misc" tab has no valid configs on Linux
   constexpr int kMiscTabIndex = 6;
   configDialogTabWidget->removeTab(kMiscTabIndex);
@@ -281,7 +283,8 @@
   dictionaryPreloadingAndUACLabel->setVisible(false);
 #endif  // _WIN32
 
-#ifdef __linux__
+#if defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   // On Linux, disable all fields for UsageStats
   usageStatsLabel->setEnabled(false);
   usageStatsLabel->setVisible(false);
