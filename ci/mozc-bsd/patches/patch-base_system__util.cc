$NetBSD: patch-base_system__util.cc,v 1.7 2024/02/10 01:17:27 ryoon Exp $

Widen the Linux arm to the BSDs, and name each of them where the name is
what is returned.

Most of the conditions here take another BSD in the same list.  Two do not.
GetOSVersionString returns the name, so the four are separate #elif arms --
folded together they would make DragonFly answer "NetBSD".  MOZC_SERVER_DIR
is substituted with the package's own PREFIX, which is right on all of them.

--- base/system_util.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ base/system_util.cc
@@ -278,7 +278,8 @@
   return FileUtil::JoinPath(dir, "Mozc");
 #endif  //  GOOGLE_JAPANESE_INPUT_BUILD
 
-#elif defined(__linux__)
+#elif defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__) || \
+    defined(__OpenBSD__) || defined(__DragonFly__)
   // 1. If "$HOME/.mozc" already exists,
   //    use "$HOME/.mozc" for backward compatibility.
   // 2. If $XDG_CONFIG_HOME is defined
@@ -429,9 +430,10 @@
   return MacUtil::GetServerDirectory();
 #endif  // __APPLE__
 
-#if defined(__linux__) || defined(__wasm__)
+#if defined(__linux__) || defined(__wasm__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
 #ifndef MOZC_SERVER_DIR
-#define MOZC_SERVER_DIR "/usr/lib/mozc"
+#define MOZC_SERVER_DIR "@PREFIX@/libexec"
 #endif  // MOZC_SERVER_DIR
   return MOZC_SERVER_DIR;
 #endif  // __linux__ || __wasm__
@@ -471,7 +473,7 @@
 #if defined(__linux__)
 
 #ifndef MOZC_DOCUMENT_DIR
-#define MOZC_DOCUMENT_DIR "/usr/lib/mozc/documents"
+#define MOZC_DOCUMENT_DIR "@PREFIX@/libexec/documents"
 #endif  // MOZC_DOCUMENT_DIR
   return MOZC_DOCUMENT_DIR;
 
@@ -661,7 +663,8 @@
 #endif  // _WIN32
 
 std::string SystemUtil::GetDesktopNameAsString() {
-#if defined(__linux__) || defined(__wasm__)
+#if defined(__linux__) || defined(__wasm__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
   const char *display = Environ::GetEnv("DISPLAY");
   if (display == nullptr) {
     return "";
@@ -834,6 +837,18 @@
 #elif defined(__linux__)
   const std::string ret = "Linux";
   return ret;
+#elif defined(__NetBSD__)
+  const std::string ret = "NetBSD";
+  return ret;
+#elif defined(__FreeBSD__)
+  const std::string ret = "FreeBSD";
+  return ret;
+#elif defined(__OpenBSD__)
+  const std::string ret = "OpenBSD";
+  return ret;
+#elif defined(__DragonFly__)
+  const std::string ret = "DragonFly";
+  return ret;
 #else   // !_WIN32 && !__APPLE__ && !__linux__
   const std::string ret = "Unknown";
   return ret;
@@ -873,7 +888,8 @@
   return total_memory;
 #endif  // __APPLE__
 
-#if defined(__linux__) || defined(__wasm__)
+#if defined(__linux__) || defined(__wasm__) || defined(__NetBSD__) || \
+    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
 #if defined(_SC_PAGESIZE) && defined(_SC_PHYS_PAGES)
   const int32_t page_size = sysconf(_SC_PAGESIZE);
   const int32_t number_of_phyisical_pages = sysconf(_SC_PHYS_PAGES);
