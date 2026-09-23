#!/bin/sh
V=/usr/pkgsrc/a/version.mk
grep -q x $V
V=$(make show-var VARNAME=PKGNAME)
[ -n "$V" ] || { echo "no"; exit 1; }
