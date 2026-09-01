$NetBSD$

NetBSD 11.99.4 or later, definitions for ELF have changed.

Elfnn_Versym used to be a struct with a vs_vers field and is now an
Elf_Half holding the version directly, so ->vs_vers no longer names
anything.  sys/exec_elf.h tells the two apart by the value of its own
guard.  devel/abseil carries the same change; this copy is bundled and
did not get it.

--- third_party/abseil-cpp/absl/debugging/internal/elf_mem_image.cc.orig	2023-10-26 12:00:50.000000000 +0000
+++ third_party/abseil-cpp/absl/debugging/internal/elf_mem_image.cc
@@ -350,7 +350,7 @@ void ElfMemImage::SymbolIterator::Update
   const ElfW(Versym) *version_symbol = image->GetVersym(index_);
   ABSL_RAW_CHECK(symbol && version_symbol, "");
   const char *const symbol_name = image->GetDynstr(symbol->st_name);
-#if defined(__NetBSD__)
+#if defined(__NetBSD__) && ((_SYS_EXEC_ELF_H_ + 0) < 2)
   const int version_index = version_symbol->vs_vers & VERSYM_VERSION;
 #else
   const ElfW(Versym) version_index = version_symbol[0] & VERSYM_VERSION;
