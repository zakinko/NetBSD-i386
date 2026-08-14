$NetBSD$

Fix a NULL dereference in the regexp parser.  CVE-2025-2588.

parse_regexp() can return NULL without recording a reason in parse->error,
and three of its callers -- fa_expand_nocase(), fa_restrict_alphabet() and
fa_expand_char_ranges() -- only look at parse->error before dereferencing
what came back.  Upstream fixed this at the source rather than adding a NULL
check to each caller:

  https://github.com/hercules-team/augeas/issues/852

The upstream commit is on master and has not been released; 1.14.1 (2023) is
still the last release.  It uses _REG_ENOSYS, which is a glibc extension and
is not in NetBSD's <regex.h>, so REG_BADPAT is used here instead.  It is
POSIX and says the same thing to the caller: the pattern was no good.

--- src/fa.c.orig	2023-07-14 11:07:23.000000000 +0000
+++ src/fa.c
@@ -3550,6 +3550,10 @@
     return re;
 
  error:
+    /* CVE-2025-2588: do not hand a NULL back with parse->error unset;
+     * the callers below only test parse->error. */
+    if (re == NULL && parse->error == REG_NOERROR)
+        parse->error = REG_BADPAT;
     re_unref(re);
     return NULL;
 }
