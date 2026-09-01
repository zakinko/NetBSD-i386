$NetBSD$

Name DragonFly in the two feature lists it belongs in.

absl/base/config.h decides these by listing platform names, and DragonFly
appears nowhere in the file -- the other three BSDs appear twice each.

Without ABSL_HAVE_MMAP the header sets ABSL_LOW_LEVEL_ALLOC_MISSING, and
low_level_alloc.cc compiles to an empty translation unit.  Nothing warns:
the failure arrives at link time as undefined symbols, several files away
from the macro that caused it.

Without ABSL_HAVE_PTHREAD_GETSCHEDPARAM abseil falls back rather than
calling the function.

Both were measured on the platform rather than assumed from it being a BSD:
mmap(MAP_ANON) returns a mapping and pthread_getschedparam returns 0 on
DragonFly 6.4, as they do on the three already listed.

--- third_party/abseil-cpp/absl/base/config.h.orig	2023-10-26 12:00:50.000000000 +0000
+++ third_party/abseil-cpp/absl/base/config.h
@@ -429,7 +429,7 @@
     defined(__asmjs__) || defined(__wasm__) || defined(__Fuchsia__) ||    \
     defined(__sun) || defined(__ASYLO__) || defined(__myriad2__) ||       \
     defined(__HAIKU__) || defined(__OpenBSD__) || defined(__NetBSD__) ||  \
-    defined(__QNX__)
+    defined(__QNX__) || defined(__DragonFly__)
 #define ABSL_HAVE_MMAP 1
 #endif
 
@@ -441,7 +441,7 @@
 #error ABSL_HAVE_PTHREAD_GETSCHEDPARAM cannot be directly set
 #elif defined(__linux__) || defined(__APPLE__) || defined(__FreeBSD__) || \
     defined(_AIX) || defined(__ros__) || defined(__OpenBSD__) ||          \
-    defined(__NetBSD__)
+    defined(__NetBSD__) || defined(__DragonFly__)
 #define ABSL_HAVE_PTHREAD_GETSCHEDPARAM 1
 #endif
 
