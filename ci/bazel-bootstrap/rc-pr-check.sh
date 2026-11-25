#!/bin/sh
# rules_cc の PR の枝を、出来た bazel で測る。ci/bazel-bsd/run.sh の rules-cc の
# 段から検査をそのまま移したもの。あちらは踏み台の bazel を probe の枝から
# 起こすが、その bootstrap が 2026-11-11 に Java の compile で落ちるように
# なった (run 42966066118)。bazel-master-sh の dist の bazel ならこの箱で
# 建っているので、その上で測る。
#
#	sh rc-pr-check.sh <bazel> <rules_cc の tar.gz> <repository_cache>
set -u
B=$1 RC_TGZ=$2 REPO_CACHE=$3
OS=$(uname -s)
W=${W:-$(dirname "$RC_TGZ")/rcpr}
mkdir -p "$W"
say() { echo "RESULT rc-pr $OS $*"; }
tc_field() {
	awk -v k="$2" '
		!inb && $0 ~ "^[ \t]*" k " = \\[" { inb = 1; print; if (/\]/) exit; next }
		inb { print; if (/\]/) exit }
	' "$1"
}
echo '##### 4. rules_cc の toolchain を測る #####'
RC=$W/rules_cc
rm -rf "$RC"; mkdir -p "$RC"
# git の無い箱でも測れるよう、workflow の側で取った archive を広げる
# OpenBSD の tar は --strip-components を持たないので、一段下を引き上げる
(cd "$RC" && tar -xzf "$RC_TGZ" && top=$(ls) && mv "$top"/* "$top"/.[!.]* . 2>/dev/null; rmdir "$top")
cat "$RC_TGZ.ref" 2>/dev/null || :

T=$W/rctest
rm -rf "$T"; mkdir -p "$T/lib"
cat > "$T/MODULE.bazel" <<'M'
module(name = "rctest")
bazel_dep(name = "rules_cc", version = "0.2.22")
M
cat > "$T/BUILD.bazel" <<'M'
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

# #854 の再現。linkstatic=False なので RPATH に $ORIGIN が入る。
cc_library(name = "func", srcs = ["lib/func.cpp"])

cc_binary(
    name = "main",
    srcs = ["main.cpp"],
    deps = [":func"],
    linkstatic = False,
)

# #857 の再現。libc++ と libc++abi が pthread を要る。
cc_binary(name = "hello", srcs = ["hello.cpp"])
M
echo 'extern int func();
int main() { return func(); }' > "$T/main.cpp"
echo 'int func() { return 0; }' > "$T/lib/func.cpp"
# echo に \n を渡さない。OpenBSD の sh (ksh) の echo は backslash を
# 解釈するので、C++ の文字列の中に生の改行が入り
#
#	hello.cpp:2:27: warning: missing terminating '"' character
#	hello.cpp:2:27: error: expected expression
#
# で compile が落ちる。#857 の回帰検査はその手前で止まるので、link を
# 一度も測らないまま「落ちた」になる。
#
#	https://github.com/zakinko/NetBSD-i386/actions/runs/35015123723
cat > "$T/hello.cpp" <<'M'
#include <iostream>
int main() { std::cout << "hello-from-rules-cc" << std::endl; }
M

cd "$T"
"$B" build --repository_cache="$REPO_CACHE" ${EXTRA_BAZEL_ARGS:-} --repo_contents_cache= --override_module=rules_cc="$RC" //... \
	|| { say "rules_cc の test workspace が建たない"; exit 1; }

fail=0

# 生成された toolchain そのものを見る。#862 の review で
#
#	should we be worried that this logic would select gcc on bsd if
#	they had that installed alongside the default?
#
# と訊かれている所で、手元で一度測って終わりにすると主張だけが残る。
# BSD の base には cc と gcc が同じものとして両方在るか、gcc が無いので、
# ここで /usr/bin/cc 以外を掴んでいたら ports や pkgsrc のものを拾って
# いる。出して、かつ落とす。
#
# 見るのは BUILD であって cc_toolchain_config.bzl ではない。後者は rule の
# 実装で、値の所は ctx.attr.compiler のような参照でしかない。そちらを
# grep して「driver の path を読み取れない」を出した。
#
#	https://github.com/zakinko/NetBSD-i386/actions/runs/35061461816
#
# 生成された値は BUILD の cc_toolchain_config(...) の中に在る。
#
# その前に、箱の compiler そのものを出しておく。#862 の返信に書いた
# 「NetBSD と DragonFly は cc と gcc が同じ物」「DragonFly に
# /usr/bin/clang も /usr/bin/dwp も無く、-lc++ は繋がらず -lstdc++ は
# 繋がる」は、消してしまった Vultr の箱で手で測った値だった。ここで
# 毎回出せば run の URL で指せる。link の probe は source ではなく
# object を渡す。source を渡すと driver が runtime を足して何でも通る。
echo "--- 箱の compiler ---"
for t in cc gcc clang c++ g++ clang++; do
	p=$(command -v "$t" 2>/dev/null || true)
	if [ -n "$p" ]; then
		printf '  %-8s %s  %s\n' "$t" "$p" "$("$p" --version 2>/dev/null | head -1)"
	else
		printf '  %-8s (無し)\n' "$t"
	fi
done
for f in /usr/bin/clang /usr/bin/dwp; do
	if [ -e "$f" ]; then echo "  $f  在る"; else echo "  $f  無い"; fi
done
echo "  -- link probe (object を渡す)"
P=$W/linkprobe
rm -rf "$P"; mkdir -p "$P"
printf 'int main(void) { return 0; }\n' > "$P/p.c"
if cc -c -o "$P/p.o" "$P/p.c" 2>"$P/cc.err"; then
	for lib in -lc++ -lstdc++ -lm -lpthread; do
		if cc -o "$P/p" "$P/p.o" "$lib" 2>"$P/l.err"; then
			printf '  cc p.o %-10s 繋がる\n' "$lib"
		else
			printf '  cc p.o %-10s 落ちる: %s\n' "$lib" "$(head -1 "$P/l.err" | cut -c1-80)"
		fi
	done
else
	echo "  cc -c が落ちた: $(head -1 "$P/cc.err")"
fi

echo "--- 生成された toolchain (#862) ---"
OB=$("$B" info output_base 2>/dev/null || true)
LCC=""
if [ -n "$OB" ]; then
	LCC=$(find "$OB/external" -maxdepth 1 -name '*local_config_cc' -type d 2>/dev/null | head -1)
fi
if [ -z "$LCC" ] || [ ! -f "$LCC/BUILD" ]; then
	say "#862 測れない: local_config_cc/BUILD が見つからない (output_base=$OB)"
	fail=1
else
	grep -E '^ *(toolchain_identifier|compiler|target_libc|host_system_name|cpu) = "' \
		"$LCC/BUILD" | sed 's/^ */  /'
	echo "  -- tool_paths"
	grep -o '"gcc": *"[^"]*"' "$LCC/BUILD" | sed 's/^/    /'
	# 一覧は必ず複数行に折れている。lib_cc_configure.bzl の
	# get_starlark_list が '",\n    "' で繋ぐためで、行単位の grep -o では
	# 一項目しかない短い key しか拾えない。実際 link_flags を指したつもりで
	# opt_link_flags と coverage_link_flags だけが出ていた。
	#
	#	https://github.com/zakinko/NetBSD-i386/actions/runs/35067051116
	#
	# key の行から始めて、] の在る行まで出す。key は行頭に錨を打つ。
	# そうしないと link_flags が opt_link_flags にも当たる。
	for k in cxx_builtin_include_directories link_flags link_libs; do
		echo "  -- $k"
		tc_field "$LCC/BUILD" "$k" | sed 's/^/    /' | head -14
	done

	drv=$(sed -n 's/.*"gcc": *"\([^"]*\)".*/\1/p' "$LCC/BUILD" | head -1)
	case "$drv" in
	*/cc)  say "#862 OK: C の driver は $drv" ;;
	"")    say "#862 測れない: driver の path を読み取れない"; fail=1 ;;
	*)     say "#862 NG: cc ではなく $drv を掴んでいる"; fail=1 ;;
	esac

	# #854 は OpenBSD の話なので、そこだけ設定の側でも断定する。
	# 他の BSD は ld が -z origin を取るとは限らないので出すだけ。
	#
	# file 全体を grep してはいけない。「link_flags に在る」と言いながら
	# 別の key に在っても通ってしまう。link_flags の中だけを見る。
	if [ "$OS" = OpenBSD ]; then
		if tc_field "$LCC/BUILD" link_flags | grep -q 'z,origin'; then
			say "#854 OK: link_flags に -z origin が在る"
		else
			say "#854 NG: link_flags に -z origin が無い"
			fail=1
		fi
	fi
fi

echo "--- NEEDED の一覧 (#857) ---"
need=""
for t in objdump readelf; do
	if command -v "$t" >/dev/null 2>&1; then need=$t; break; fi
done
case "$need" in
objdump) objdump -p bazel-bin/hello | grep NEEDED || true ;;
readelf) readelf -d bazel-bin/hello | grep NEEDED || true ;;
*)       ldd bazel-bin/hello || true ;;
esac
if [ "$OS" = OpenBSD ]; then
	if { objdump -p bazel-bin/hello 2>/dev/null || readelf -d bazel-bin/hello 2>/dev/null; } \
	   | grep -q 'pthread'; then
		say "#857 OK: libpthread が NEEDED に居る"
	else
		say "#857 NG: libpthread が NEEDED に無い"
		fail=1
	fi
fi

echo "--- 走らせる (#857) ---"
./bazel-bin/hello > "$T/hello.out" 2> "$T/hello.err" || true
cat "$T/hello.out"; cat "$T/hello.err"
if grep -q 'undefined symbol' "$T/hello.err"; then
	say "#857 NG: undefined symbol が出た"
	fail=1
else
	say "#857 OK: undefined symbol は出ない"
fi

# 走ることだけを見てはいけない。RPATH に $ORIGIN が入っていなければ、
# あるいは共有 library を要求していなければ、当て物を外しても走ってしまい、
# 検査が何も測らないまま緑になる。測る物が在ることを先に確かめる。
echo "--- \$ORIGIN (#854) ---"
dyn=$({ objdump -p bazel-bin/main 2>/dev/null || readelf -d bazel-bin/main 2>/dev/null; })
echo "$dyn" | grep -E 'RPATH|RUNPATH|NEEDED' || true
# $ORIGIN が RPATH に入っていれば、共有 library をそこから引く形になって
# いる。入っていなければ静的に繋がったということで、DF_ORIGIN の有無を
# 測れる状態ではない。NEEDED の名前は箱ごとに違いうるので断定せず、
# 記録に残すだけにする。
if ! echo "$dyn" | grep -qE '(RPATH|RUNPATH).*\$ORIGIN'; then
	say "#854 測れない: RPATH に \$ORIGIN が無い (linkstatic=False が効いていない)"
	fail=1
elif ./bazel-bin/main > "$T/main.out" 2> "$T/main.err"; then
	say "#854 OK: \$ORIGIN 付きの binary が走る"
else
	cat "$T/main.err"
	say "#854 NG: \$ORIGIN 付きの binary が走らない"
	fail=1
fi

# cc_static_library の検査 (validate_static_library.sh) を、bash を呼ばずに
# 走らせられるか。重複の無い物は建ち、重複の在る物は "Duplicate symbols" で
# 落ちることを見る。落ちる側を見ないと、検査が走らずに素通りしても緑になる。
# bash の記録 wrapper が張られている箱では、この二回の build の間に bash を
# 何回呼んだかも数える。
echo "--- cc_static_library (validate_static_library) ---"
mkdir -p "$T/sl"
echo 'int sl_a(void) { return 1; }' > "$T/sl/a.c"
echo 'int sl_b(void) { return 2; }' > "$T/sl/b.c"
echo 'int sl_a(void) { return 3; }' > "$T/sl/dup.c"
cat > "$T/sl/BUILD.bazel" <<'M'
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:cc_static_library.bzl", "cc_static_library")

cc_library(name = "a", srcs = ["a.c"])
cc_library(name = "b", srcs = ["b.c"])
cc_library(name = "dup", srcs = ["dup.c"])

cc_static_library(name = "ok", deps = [":a", ":b"])
cc_static_library(name = "bad", deps = [":a", ":dup"], tags = ["manual"])
M
nb0=0
[ -n "${BASHLOG:-}" ] && [ -f "$BASHLOG" ] && nb0=$(wc -l < "$BASHLOG" | tr -d ' ')
VSL=$(find "$LCC" -name validate_static_library.sh 2>/dev/null | head -1)
if [ -z "$VSL" ]; then
	say "static 測れない: validate_static_library.sh が生成されていない (nm か c++filt が無い)"
	fail=1
else
	echo "  $(head -1 "$VSL")  ($VSL)"
	DSW=$(find "$LCC" -name deps_scanner_wrapper.sh 2>/dev/null | head -1)
	[ -n "$DSW" ] && echo "  $(head -1 "$DSW")  ($DSW)"
	if "$B" build --repository_cache="$REPO_CACHE" ${EXTRA_BAZEL_ARGS:-} --repo_contents_cache= \
		--override_module=rules_cc="$RC" //sl:ok > "$T/sl-ok.log" 2>&1; then
		say "static OK: 重複の無い cc_static_library が建つ"
	else
		tail -20 "$T/sl-ok.log"
		say "static NG: 重複の無い cc_static_library が建たない"
		fail=1
	fi
	if "$B" build --repository_cache="$REPO_CACHE" ${EXTRA_BAZEL_ARGS:-} --repo_contents_cache= \
		--override_module=rules_cc="$RC" //sl:bad > "$T/sl-bad.log" 2>&1; then
		say "static NG: 重複の在る cc_static_library が通ってしまった"
		fail=1
	elif grep -q 'Duplicate symbols found' "$T/sl-bad.log"; then
		grep -A3 'Duplicate symbols found' "$T/sl-bad.log" | head -4
		say "static OK: 重複を Duplicate symbols で落とす"
	else
		tail -20 "$T/sl-bad.log"
		say "static NG: 重複の在る物が別の理由で落ちた"
		fail=1
	fi
fi
# C++20 module の scan (deps_scanner_wrapper.sh)。gcc は 14 から scan できる。
# clang は clang-scan-deps が要り、BSD の base には無いので Linux だけで見る。
# 見るのは scan の action だけで、その後の compile が通るかは問わない。
if [ "$OS" = Linux ]; then
	mkdir -p "$T/mod"
	printf 'export module m;\nexport int f() { return 42; }\n' > "$T/mod/m.cppm"
	cat > "$T/mod/BUILD.bazel" <<'M'
load("@rules_cc//cc:cc_library.bzl", "cc_library")

cc_library(name = "m", module_interfaces = ["m.cppm"], features = ["cpp_modules"], copts = ["-std=c++20"], tags = ["manual"])
M
	"$B" build --repository_cache="$REPO_CACHE" ${EXTRA_BAZEL_ARGS:-} --repo_contents_cache= \
		--override_module=rules_cc="$RC" --experimental_cpp_modules //mod:m > "$T/mod.log" 2>&1
	if grep -q 'Deps scanning .* failed' "$T/mod.log"; then
		grep -E 'Deps scanning|env:' "$T/mod.log" | cut -c1-200 | head -3
		say "module scan NG: $(grep -o 'Deps scanning .* failed: ([^)]*)' "$T/mod.log" | head -1)"
		fail=1
	elif [ -n "$(find -L "$T/bazel-out" -name '*.ddi' 2>/dev/null | head -1)" ]; then
		say "module scan OK: .ddi が出来た"
	else
		tail -8 "$T/mod.log"
		say "module scan 測れない"
	fi
fi
if [ -n "${BASHLOG:-}" ] && [ -f "$BASHLOG" ]; then
	nb1=$(wc -l < "$BASHLOG" | tr -d ' ')
	tail -n +$((nb0 + 1)) "$BASHLOG" | head -5
	say "static bash-calls $((nb1 - nb0))"
fi

if [ $fail -eq 0 ]; then
	say "段 rules-cc まで完了"
	exit 0
fi
say "rules-cc の検査が落ちた"
exit 1
