$NetBSD$

NetBSD support for the GYP build, needed by the "gyp" package option.

Upstream build_mozc.py has no NetBSD branch in any release; the gyp
command dies in AddTargetPlatformOption with UnboundLocalError before it
parses anything.

--- build_mozc.py.orig	2023-10-26 12:00:50.000000000 +0000
+++ build_mozc.py
@@ -54,6 +54,8 @@
 from build_tools.util import ColoredText
 from build_tools.util import CopyFile
 from build_tools.util import IsLinux
+from build_tools.util import IsBSD
+from build_tools.util import IsNetBSD
 from build_tools.util import IsMac
 from build_tools.util import IsWindows
 from build_tools.util import PrintErrorAndExit
@@ -98,6 +100,10 @@
       'Windows': 'out_win',
       'Mac': 'out_mac',
       'Linux': 'out_linux',
+      'NetBSD': 'out_bsd',
+      'FreeBSD': 'out_bsd',
+      'OpenBSD': 'out_bsd',
+      'DragonFly': 'out_bsd',
   }
 
   if target_platform not in platform_dict:
@@ -160,7 +166,7 @@
   # Include subdirectory of win32 and breakpad for Windows
   if options.target_platform == 'Windows':
     gyp_file_names.extend(glob.glob('%s/win32/*/*.gyp' % OSS_SRC_DIR))
-  elif options.target_platform == 'Linux':
+  elif options.target_platform in ('Linux', 'NetBSD', 'FreeBSD', 'OpenBSD', 'DragonFly'):
     gyp_file_names.extend(glob.glob('%s/unix/emacs/*.gyp' % OSS_SRC_DIR))
   gyp_file_names.sort()
   return gyp_file_names
@@ -181,7 +187,9 @@
 
 # TODO(b/68382821): Remove this method. We no longer need --target_platform.
 def AddTargetPlatformOption(parser):
-  if IsLinux():
+  if IsBSD():
+    default_target = IsBSD()
+  elif IsLinux():
     default_target = 'Linux'
   elif IsWindows():
     default_target = 'Windows'
