$NetBSD$

NetBSD support for the GYP build, needed by the "gyp" package option.

Without the ldflags, linking protoc fails with an undefined reference to
pthread_getschedparam.

inputmethod/mozc-server226 also flips the make_global_settings block for
NetBSD, which hardcodes the compiler with which(1).  That is left out here;
pkgsrc supplies the compiler through its wrappers.

--- gyp/common.gypi.orig	2023-10-26 12:00:50.000000000 +0000
+++ gyp/common.gypi
@@ -74,6 +74,14 @@
       '-fstack-protector',
       '--param=ssp-buffer-size=4',
     ],
+    # netbsd_cflags will be used for NetBSD.
+    'netbsd_cflags': [
+      '<@(gcc_cflags)',
+      '-fPIC',
+      '-D_NETBSD_SOURCE',
+      '-fno-exceptions',
+      '<!(echo $CFLAGS)',
+    ],
     # mac_cflags will be used in Mac.
     # Xcode 4.5 which we are currently using does not support ssp-buffer-size.
     # TODO(horo): When we can use Xcode 4.6 which supports ssp-buffer-size,
@@ -103,6 +111,15 @@
         'compiler_target': 'gcc',
         'compiler_host': 'gcc',
       }],
+      # mozc 自身が持つ値なので四つとも素直に足せる。gyp の OS== の方は
+      # flavor が別に決まるので、そちらは別に扱う。
+      ['target_platform=="NetBSD" or target_platform=="FreeBSD" or \
+        target_platform=="OpenBSD" or target_platform=="DragonFly"', {
+        'compiler_target': 'gcc',
+        'compiler_target_version_int': 409,  # GCC 4.9 or higher
+        'compiler_host': 'gcc',
+        'compiler_host_version_int': 409,  # GCC 4.9 or higher
+      }],
     ],
   },
   'target_defaults': {
@@ -228,6 +245,24 @@
           }],
         ],
       }],
+      ['OS=="netbsd"', {
+        'defines': [
+          'OS_NETBSD',
+        ],
+        'cflags': [
+          '<@(netbsd_cflags)',
+          '-fPIC',
+          '-fno-exceptions',
+        ],
+        'cflags_cc': [
+          # We use deprecated <hash_map> and <hash_set> instead of upcoming
+          # <unordered_map> and <unordered_set>.
+          '-Wno-deprecated',
+        ],
+        'ldflags': [
+          '-pthread',
+        ],
+      }],
       ['OS=="mac"', {
         'defines': [
           '__APPLE__',
