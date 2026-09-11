$NetBSD$

Do not define _XOPEN_SOURCE on DragonFly.

Proposed upstream as abseil/abseil-cpp#2160; drop this patch once that
lands.  Upstream already excludes OpenBSD here for the same kind of reason.

cctz defines _XOPEN_SOURCE itself, for strptime.  On DragonFly that moves
__ISO_C_VISIBLE from 2011 down to 1990, and libstdc++'s <cwchar> then fails
on the C99 wide-character functions it expects:

  /usr/include/c++/8.0/cwchar:164:11: error: '::vfwscanf' has not been declared

Measured by compiling <cwchar> with and without -D_XOPEN_SOURCE=500 on each
system.  DragonFly is the only one that breaks: FreeBSD goes 2023 -> 2011,
OpenBSD stays at 2011, and NetBSD does not define __ISO_C_VISIBLE at all.

This file is compiled here -- mozc links absl/time, and cctz comes with it.

--- third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc
@@ -19,7 +19,7 @@
 #endif
 
 #if defined(HAS_STRPTIME) && HAS_STRPTIME
-#if !defined(_XOPEN_SOURCE) && !defined(__OpenBSD__)
+#if !defined(_XOPEN_SOURCE) && !defined(__OpenBSD__) && !defined(__DragonFly__)
 #define _XOPEN_SOURCE  // Definedness suffices for strptime.
 #endif
 #endif
