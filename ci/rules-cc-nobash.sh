#!/bin/sh
# bash を外した Debian で、rules_cc の枝ごと・compiler ごとに
# C++20 module と cc_static_library を建てる。.github/workflows/rules-cc-nobash.yml から。
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -q >/dev/null
apt-get install -y -q gcc g++ clang clang-tools ca-certificates git >/dev/null 2>&1
gcc --version | head -1; clang --version | head -1
CLANG=$(dirname "$(readlink -f "$(command -v clang)")")/clang
ls -l "$(dirname "$CLANG")/clang-scan-deps"
rm -f /bin/bash /usr/bin/bash
if command -v bash; then echo "bash が残っている"; exit 1; fi

T=/t; mkdir -p $T/log.d /ob
cat > $T/MODULE.bazel <<'M'
module(name = "t")
bazel_dep(name = "rules_cc", version = "0.2.22")
M
cat > $T/BUILD.bazel <<'M'
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_static_library.bzl", "cc_static_library")

cc_library(name = "m", module_interfaces = ["m.cppm"], features = ["cpp_modules"], copts = ["-std=c++20"])
cc_binary(name = "usem", srcs = ["usem.cc"], deps = [":m"], features = ["cpp_modules"], copts = ["-std=c++20"])
cc_library(name = "a", srcs = ["a.c"])
cc_library(name = "b", srcs = ["b.c"])
cc_library(name = "dup", srcs = ["dup.c"])
cc_static_library(name = "ok", deps = [":a", ":b"])
cc_static_library(name = "bad", deps = [":a", ":dup"], tags = ["manual"])
M
printf 'export module m;\nexport int f() { return 42; }\n' > $T/m.cppm
printf 'import m;\nint main() { return f() == 42 ? 0 : 1; }\n' > $T/usem.cc
echo 'int sl_a(void) { return 1; }' > $T/a.c
echo 'int sl_b(void) { return 2; }' > $T/b.c
echo 'int sl_a(void) { return 3; }' > $T/dup.c
cd $T
LOG=$T/log.d/log
for r in $REFS; do
	for c in gcc clang; do
		case $c in gcc) CC=/usr/bin/gcc ;; clang) CC=$CLANG ;; esac
		export CC
		B="/w/bazel --batch --output_user_root=/ob/$r-$c"
		build() { $B build --experimental_cpp_modules --override_module=rules_cc=/w/rc/$r --repo_env=CC="$CC" --verbose_failures "$@"; }
		say() { echo "RESULT $r $c $*"; }
		show() { grep -E 'Exit|env:|ERROR|rror:' $LOG | cut -c1-260 | head -6; }
		rc=0; build //:usem > $LOG 2>&1 || rc=$?
		if [ $rc = 0 ] && ./bazel-bin/usem; then say "module: 建って走った"; else say "module: 落ちた rc=$rc"; show; fi
		L=$($B info output_base 2>/dev/null || :)/external
		for s in deps_scanner_wrapper.sh validate_static_library.sh; do f=$(find "$L" -name $s 2>/dev/null | head -1); if [ -n "$f" ]; then say "$s $(head -1 "$f")"; fi; done
		say "ddi $(find -L bazel-out/ -name '*.ddi' 2>/dev/null | wc -l)"
		rc=0; build //:ok > $LOG 2>&1 || rc=$?
		say "static ok: rc=$rc"; [ $rc = 0 ] || show
		rc=0; build //:bad > $LOG 2>&1 || rc=$?
		say "static bad: rc=$rc Duplicate=$(grep -c 'Duplicate symbols found' $LOG || :)"
	done
done
