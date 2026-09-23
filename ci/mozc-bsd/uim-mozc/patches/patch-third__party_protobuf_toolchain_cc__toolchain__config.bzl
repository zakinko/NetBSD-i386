$NetBSD: patch-third__party_protobuf_toolchain_cc__toolchain__config.bzl,v 1.1 2024/02/10 02:20:19 ryoon Exp $

Look for headers under the package's prefix.

The toolchain lists /usr/local/include as a builtin include directory,
which is where FreeBSD's ports put things and not where pkgsrc does.
Without the prefix the compiler does not see the headers buildlink has
staged, and bazel rejects any -I that points outside the listed roots.

--- third_party/protobuf/toolchain/cc_toolchain_config.bzl.orig	2023-12-13 11:45:04.226274104 +0000
+++ third_party/protobuf/toolchain/cc_toolchain_config.bzl
@@ -206,7 +206,7 @@ def _impl(ctx):
         cxx_builtin_include_directories = [
             ctx.attr.sysroot,
             ctx.attr.extra_include,
-            "/usr/local/include",
+            "@PREFIX@/include",
             "/usr/local/lib/clang",
         ],
         features = features,
