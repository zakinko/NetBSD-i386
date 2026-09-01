$NetBSD: patch-gui_config__dialog_keybinding__editor.cc,v 1.5 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs.

mozc knows Linux, macOS and Windows.  The pkgsrc patches added NetBSD; the
same condition holds on FreeBSD, OpenBSD and DragonFly, which upstream does
not name anywhere in src/ipc or src/base.

--- gui/config_dialog/keybinding_editor.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ gui/config_dialog/keybinding_editor.cc
@@ -111,7 +111,8 @@
         {Qt::Key_Hiragana_Katakana, "Hiragana"},
         {Qt::Key_Eisu_toggle, "Eisu"},
         {Qt::Key_Zenkaku_Hankaku, "Hankaku/Zenkaku"},
-#ifdef __linux__
+#if defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
         // On Linux (X / Wayland), Hangul and Hanja are identical with
         // ImeOn and ImeOff.
         // https://github.com/google/mozc/issues/552
@@ -361,7 +362,8 @@
       return Encode(result);
     }
   }
-#elif __linux__
+#elif defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   // The XKB defines three types of logical key code: "xkb::Hiragana",
   // "xkb::Katakana" and "xkb::Hiragana_Katakana".
   // On most of Linux distributions, any key event against physical
@@ -460,7 +462,8 @@
 KeyBindingEditor::KeyBindingEditor(QWidget *parent, QWidget *trigger_parent)
     : QDialog(parent), trigger_parent_(trigger_parent) {
   setupUi(this);
-#if defined(__linux__)
+#if defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   // Workaround for the issue https://github.com/google/mozc/issues/9
   // Seems that even after clicking the button for the keybinding dialog,
   // the edit is not raised. This might be a bug of setFocusProxy.
