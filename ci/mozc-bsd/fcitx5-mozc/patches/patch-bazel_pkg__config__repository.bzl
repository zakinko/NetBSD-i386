$NetBSD: patch-bazel_pkg__config__repository.bzl,v 1.1 2024/02/10 12:26:01 ryoon Exp $

Ask pkg-config for the whole link line, not only the -l flags.

--libs-only-l drops -L, so the libraries pkgsrc installs under its own
prefix are named but never found: the link fails on a system where the
dependency does not also sit in /usr/lib.

--- bazel/pkg_config_repository.bzl.orig	2023-12-14 08:51:15.941327119 +0000
+++ bazel/pkg_config_repository.bzl
@@ -103,7 +103,7 @@ def _pkg_config_repository_impl(repo_ctx
         "hdrs": _make_strlist([item + "/**" for item in includes]),
         "copts": _make_strlist(_exec_pkg_config(repo_ctx, "--cflags-only-other")),
         "includes": _make_strlist(includes),
-        "linkopts": _make_strlist(_exec_pkg_config(repo_ctx, "--libs-only-l")),
+        "linkopts": _make_strlist(_exec_pkg_config(repo_ctx, "--libs")),
     }
     build_file_data = BUILD_TEMPLATE.format(**data)
 
