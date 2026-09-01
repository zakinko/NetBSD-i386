$NetBSD$

NetBSD support for the GYP build, needed by the "gyp" package option.

The digit replaces the last digit of the version string (see
_GetRevisionForPlatform), and the resulting string is what the client and
the server compare when a session is created.  It is deliberately the same
digit as Linux, so that a package built with the gyp option reports the
same version as one built with bazel; bazel does not go through this table
and produces the version in DISTNAME unchanged.  With a different digit the
two builds carry the same PKGNAME but refuse to talk to each other.

inputmethod/mozc-server226 uses '8' here.  That is correct there: it has no
bazel build to agree with, and both its server and its helper come out of
the same gyp run.

--- build_tools/mozc_version.py.orig
+++ build_tools/mozc_version.py
@@ -67,6 +67,7 @@
     'iOS': '6',
     'iOS_sim': '6',
     'Wasm': '7',
+    'NetBSD': '2',
 }
 
 VERSION_PROPERTIES = [
