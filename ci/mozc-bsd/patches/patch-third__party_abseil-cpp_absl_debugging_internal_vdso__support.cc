$NetBSD$

Give DragonFly the same auxv type names as FreeBSD.

vdso_support.cc is compiled here -- mozc pulls in absl/debugging, and
ABSL_HAVE_VDSO_SUPPORT follows ABSL_HAVE_ELF_MEM_IMAGE, which is on for
every __ELF__ platform except the handful this file names.  It then wants
Elf64_auxv_t, and upstream supplies that name only for NetBSD and FreeBSD.

Measured on DragonFly 6.4:

  Elf64_Auxinfo               present
  Elf64_Auxinfo.a_un.a_val    present
  Elf64_Auxinfo.a_v           absent
  Aux64Info                   absent

so the FreeBSD spelling fits, and the member the value is read through is
a_un.a_val, which is what the #else arm further down already uses.  Only
the type names are missing; nothing else in this file needs a DragonFly
arm.  (NetBSD is the odd one there: its Aux64Info carries a_v instead.)

--- third_party/abseil-cpp/absl/debugging/internal/vdso_support.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ third_party/abseil-cpp/absl/debugging/internal/vdso_support.cc
@@ -54,7 +54,7 @@
 using Elf32_auxv_t = Aux32Info;
 using Elf64_auxv_t = Aux64Info;
 #endif
-#if defined(__FreeBSD__)
+#if defined(__FreeBSD__) || defined(__DragonFly__)
 #if defined(__ELF_WORD_SIZE) && __ELF_WORD_SIZE == 64
 using Elf64_auxv_t = Elf64_Auxinfo;
 #endif
