# $NetBSD$

PKG_OPTIONS_VAR=	PKG_OPTIONS.mozc
PKG_SUPPORTED_OPTIONS=	gyp

.include "../../mk/bsd.prefs.mk"

# mozc can be built either with bazel, which is what upstream tests, or with
# gyp, which upstream keeps in maintenance mode.  The gyp build needs neither
# bazel nor a JDK, but upstream has dropped the ibus client and the GTK
# candidate window from it, so only inputmethod/mozc-server and
# inputmethod/mozc-elisp include this file.
#
# bazel can be used on two platforms and no others.  devel/bazel wants a
# JVM -- PKG_JVMS_ACCEPTED= openjdk11 -- and mk/java-vm.mk names where that
# exists:
#
#	_ONLY_FOR_PLATFORMS.openjdk11= x86_64 i386 aarch64 earmv[67]hf
#
# so powerpc64, riscv64, mips64, sparc64, alpha and ia64 have no JVM at all,
# and of the four that do, i386 and earmv[67]hf are 32-bit, where bazel does
# not build.  That leaves x86_64 and aarch64.
#
# devel/bazel marks the 32-bit platforms broken itself, as of its Makefile
# 1.17; before that a second assignment overwrote the line that said so, and
# nothing stopped a 32-bit build from being attempted.  That was pkg/60666.
#
# Test for the two that work rather than listing the many that do not, so a
# platform added later defaults to the build that has a chance of running.
.if ${OPSYS} != "NetBSD" || \
    (${MACHINE_ARCH} != "x86_64" && ${MACHINE_ARCH} != "aarch64")
PKG_SUGGESTED_OPTIONS+=	gyp
.endif

# The option is acted on in Makefile.common rather than here, because
# inputmethod/mozc-tool, inputmethod/mozc-renderer and inputmethod/ibus-mozc
# share that file without including this one, and they have no gyp build to
# choose.  Keeping the .if there lets them take the bazel branch unchanged.
.include "../../mk/bsd.options.mk"

# Both builds produce the same version string, so packages built either way
# are interchangeable at run time; see patch-build__tools_mozc__version.py
# for why that needs saying.
