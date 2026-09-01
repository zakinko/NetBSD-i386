$NetBSD: patch-gui_config__dialog_keymap__editor.cc,v 1.4 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- gui/config_dialog/keymap_editor.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ gui/config_dialog/keymap_editor.cc
@@ -441,7 +441,8 @@
   absl::StrAppend(keymap_table, invisible_keymap_table_);
 
   if (new_direct_mode_commands != direct_mode_commands_) {
-#if defined(_WIN32) || defined(__linux__)
+#if defined(_WIN32) || defined(__linux__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
     QMessageBox::information(
         this, windowTitle(),
         tr("Changes of keymaps for direct input mode will apply only to "
