$NetBSD$

NetBSD support for the GYP build, needed by the "gyp" package option.

--- build_tools/util.py.orig	2023-10-26 12:00:50.000000000 +0000
+++ build_tools/util.py
@@ -103,6 +103,24 @@
   return abs_path
 
 
+def IsNetBSD():
+  """Returns true if the platform is NetBSD."""
+  return os.name == 'posix' and os.uname()[0] == 'NetBSD'
+
+
+def IsBSD():
+  """Returns the name of the BSD being built on, or None.
+
+  The four are handled alike everywhere the build system asks: they share an
+  output directory and a version digit.  What differs is the name itself, so
+  this hands the name back rather than a boolean.
+  """
+  if os.name != 'posix':
+    return None
+  name = os.uname()[0]
+  return name if name in ('NetBSD', 'FreeBSD', 'OpenBSD', 'DragonFly') else None
+
+
 def GetNumberOfProcessors():
   """Returns the number of CPU cores available.
 
