$NetBSD: patch-base_port.h,v 1.6 2024/02/10 01:17:27 ryoon Exp $

Name each BSD in PlatformType rather than folding them together.

kTargetPlatform is chosen by an #elif chain, so the BSDs cannot share an arm:
whichever is named first would swallow the rest, and DragonFly would report
itself as NetBSD.  Each gets its own enumerator and its own arm.

--- base/port.h.orig	2023-10-26 12:00:50.000000000 +0000
+++ base/port.h
@@ -45,6 +45,10 @@
   kIPhone,    // Darwin-based firmware, devices, or simulator
   kWASM,      // WASM
   kChromeOS,  // ChromeOS
+  kNetBSD,     // NetBSD
+  kFreeBSD,    // FreeBSD
+  kOpenBSD,    // OpenBSD
+  kDragonFly,  // DragonFly BSD
 };
 
 // kTargetPlatform is the current build target platform.
@@ -68,6 +72,14 @@
 #endif                   // !TARGET_OS_IPHONE
 #elif defined(__wasm__)  // __APPLE__
 inline constexpr PlatformType kTargetPlatform = PlatformType::kWASM;
+#elif defined(__NetBSD__)
+inline constexpr PlatformType kTargetPlatform = PlatformType::kNetBSD;
+#elif defined(__FreeBSD__)
+inline constexpr PlatformType kTargetPlatform = PlatformType::kFreeBSD;
+#elif defined(__OpenBSD__)
+inline constexpr PlatformType kTargetPlatform = PlatformType::kOpenBSD;
+#elif defined(__DragonFly__)
+inline constexpr PlatformType kTargetPlatform = PlatformType::kDragonFly;
 #else                    // __wasm__
 #error "Unsupported target platform."
 #endif  // !__wasm__
