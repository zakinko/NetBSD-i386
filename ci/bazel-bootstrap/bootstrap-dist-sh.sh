#!/bin/sh
# 手元にある dist archive を、$SH_BIN だけで bootstrap し、出来た bazel で煙試験
# まで通す。dist は make-master-dist.sh が枝から作った物 (OS に依らない)。
#
# 使い方: bootstrap-dist-sh.sh <dist.zip>
#   SH_BIN       compile.sh を起動する shell と genrule の shell (既定 /bin/sh)
#   LOG_BASH     1 なら /bin/bash を記録 wrapper に差し替えて、bootstrap の間に
#                誰が bash を呼んだかを数える (root か sudo が要る)
#   NO_VIS       1 なら --check_visibility=false。master の bazel が rules_python
#                1.7.0 を visibility で弾く (bash でも同じ) のを越えるため
#   EXTRA_PATCH  dist に当てる当て物 (Alpine の musl 用など)
#   JAVA_HOME    必須
set -eu

DIST=$1
# 同梱の当て物と script は cd する前に絶対 path で覚える。相対のままだと
# $WORK へ移ったあとで見つからない (Alpine で rules_java の当て物が見つからず落ちた)。
CI_DIR=$(cd "$(dirname "$0")" && pwd)
SH_BIN=${SH_BIN:-/bin/sh}
LOG_BASH=${LOG_BASH:-0}
NO_VIS=${NO_VIS:-0}
EXTRA_PATCH=${EXTRA_PATCH:-}
WORK=${WORK:-$PWD/dist-sh-work}
OS=$(uname -s)

echo "=== JDK / OS / sh"
"${JAVA_HOME:?JAVA_HOME が要る}/bin/javac" -version
uname -srm; "$SH_BIN" -c 'echo "sh は $0"'
[ -f "$DIST" ] || { echo "$DIST が無い"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK/dist"
( cd "$WORK/dist" && unzip -q "$DIST" )
cd "$WORK/dist"
for f in compile.sh scripts/bootstrap/compile.sh scripts/bootstrap/buildenv.sh scripts/bootstrap/bootstrap.sh; do
	head -1 "$f" | grep -q '^#!/bin/sh$' || { echo "$f の shebang が #!/bin/sh でない (dist に枝の変更が入っていない)"; exit 1; }
done
if [ -n "$EXTRA_PATCH" ]; then
	echo "=== 当て物を当てる ($EXTRA_PATCH)"
	patch -p1 -f -i "$EXTRA_PATCH" </dev/null
fi
# musl の箱 (Alpine, Void musl, Chimera) は unix_jni.h の stat64 で翻訳できない。
# 当て物 (= bazelbuild/bazel へ出す物と同じ) を、ld-musl の有無で自動で当てる。
if [ "$OS" = Linux ] && ls /lib/ld-musl-* >/dev/null 2>&1; then
	if [ "${NO_MUSL_PATCH:-0}" = 1 ]; then
		# 当て物を外して、上流へ出す本文が引用している error を実際に出す。
		# 引用の出所が「昔どこかで見た」では根拠にならない。当て物が入った
		# 木でしか測っていないと、当て物が効いているのか、そもそも問題が
		# 起きないのかも区別できない
		echo "=== musl: NO_MUSL_PATCH=1 なので当て物を当てない (error を出すため)"
	else
		echo "=== musl: unix_jni.h の当て物を当てる"
		patch -p1 -f -i "$CI_DIR/musl-stat-master.patch" </dev/null
	fi
fi

# BSD では rules_python が配る CPython が無く、MODULE.bazel の pip.parse が
# 評価の時点で interpreter を要って module extension ごと落ちる
# (hub_builder.bzl の Traceback)。pip の塊を使うのは bazel_nojdk の graph の
# 外だけなので、踏み台を建てる間は落とす。zakinko/bazel の
# probe/plain-upstream の ci/master-bootstrap.sh と同じ手当て。
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|OpenBSD|NetBSD|DragonFly)
	echo "=== pip の塊を落とす (BSD)"
	python3 "$CI_DIR/drop_pip_dev_deps.py" .
	if grep -rq bazel_pip_dev_deps MODULE.bazel third_party/py 2>/dev/null; then
		echo "pip の塊が残っている"; exit 1
	fi
	# master が固定する protobuf 36 は、_POSIX_C_SOURCE を define するせいで
	# BSD の libc++ の <locale> が isascii を見失って翻訳できない
	# (protocolbuffers/protobuf#29694 で直しを出してある)。bazel は protobuf に
	# 自前の当て物 (third_party/protobuf.patch) を差しているので、その末尾に
	# 同じ 6 行を足す。sh 化とは無関係で、bash で建てても同じ所で落ちる。
	echo "=== protobuf #29694 を third_party/protobuf.patch に足す (BSD)"
	cat "$CI_DIR/protobuf-29694.patch" >> third_party/protobuf.patch ;;
esac

# NetBSD と DragonFly は master が host として未対応 (#31069 が open)。#31069 の
# diff を dist に当て (build_unix_jni.sh の腕は sh 形に写した物、unix_jni.h は
# musl の当て物が代わり)、platforms / rules_java / zstd-jni / rules_go に
# NetBSD の当て物を single_version_override で差す。pkgsrc の bazel9 が
# 9.2.0 に対してしている物と同じ束。
case "$OS" in
NetBSD|DragonFly)
	NB=$CI_DIR/netbsd
	echo "=== NetBSD/DragonFly: bazel #31069 と module の当て物を差す"
	patch -p1 -f -i "$NB/bazel-31069-netbsd.patch" </dev/null
	patch -p1 -f -i "$NB/build_unix_jni-netbsd.patch" </dev/null
	patch -p1 -f -i "$NB/build_unix_jni-dragonfly.patch" </dev/null
	patch -p1 -f -i "$CI_DIR/musl-stat-master.patch" </dev/null
	# DragonFly は master にも #31069 にも入っていないので、NetBSD の分の上に
	# 同じ形で足す (src/conditions から unix_jni_bsd.cc まで)
	if [ "$OS" = DragonFly ]; then
		patch -p1 -f -i "$NB/bazel-dragonfly.patch" </dev/null
	fi
	# NetBSD の patch(1) は "new file mode 100755" を見ないので、当て物が作った
	# script に実行の印が付かず、sh_binary が「実行できない」と言って落ちる
	# (run 35749586358)。付け直す
	chmod +x src/md5_netbsd.sh
	RJ=$(grep -o 'name = "rules_java", version = "[^"]*"' MODULE.bazel | sed 's/.*version = "//; s/"//')
	RG=$(grep -o 'name = "rules_go", version = "[^"]*"' MODULE.bazel | sed 's/.*version = "//; s/"//')
	[ -f "$CI_DIR/rules_java-$RJ-local.patch" ] || { echo "rules_java $RJ 向けの当て物が無い"; exit 1; }
	mkdir -p toolchain_local
	cp "$NB/platforms-pr142-pr143.patch" "$NB/zstd_jni-netbsd.patch" \
		"$NB/zstd_jni-module.patch" "$NB/rules_go-pr4711.patch" toolchain_local/
	cp "$CI_DIR/rules_java-$RJ-local.patch" toolchain_local/rules_java-local.patch
	cp "$NB/abseil-dragonfly.patch" "$NB/c-ares-dragonfly.patch" \
		"$NB/grpc-dragonfly.patch" toolchain_local/
	cp "$NB/rules_java-dragonfly.patch" toolchain_local/
	printf 'exports_files(glob(["*.patch"]))\n' > toolchain_local/BUILD
	# c-ares は dist の MODULE.bazel が既に single_version_override で版を
	# 決めている。二つ目を足すと "multiple overrides for dep c-ares" になる
	# (run 35774683548) ので、在る方へ patches を差し込む
	awk '
		/module_name = "grpc"/ { ingrpc = 1 }
		ingrpc && /patches = \[/ {
			print "    patches = ["
			print "        \"//third_party:grpc-load-fixes.patch\","
			print "        \"//toolchain_local:grpc-dragonfly.patch\","
			print "    ]," 
			ingrpc = 0
			next
		}
		/module_name = "c-ares"/ { inca = 1 }
		inca && /^\)/ {
			print "    patch_strip = 1,"
			print "    patches = [\"//toolchain_local:c-ares-dragonfly.patch\"],"
			inca = 0
		}
		{ print }
	' MODULE.bazel > MODULE.bazel.new && mv MODULE.bazel.new MODULE.bazel
	for want in c-ares-dragonfly.patch grpc-dragonfly.patch; do
		grep -q "$want" MODULE.bazel || { echo "override に $want を差せなかった"; exit 1; }
	done
	cat >> MODULE.bazel <<MOD

# NetBSD is not among the platforms these modules know about (CI only).
single_version_override(
    module_name = "platforms",
    patch_strip = 1,
    patches = ["//toolchain_local:platforms-pr142-pr143.patch"],
)
single_version_override(
    module_name = "rules_java",
    version = "$RJ",
    patch_strip = 1,
    patches = [
        "//toolchain_local:rules_java-local.patch",
        "//toolchain_local:rules_java-dragonfly.patch",
    ],
)
single_version_override(
    module_name = "zstd-jni",
    patch_strip = 1,
    patches = [
        "//toolchain_local:zstd_jni-module.patch",
        "//toolchain_local:zstd_jni-netbsd.patch",
    ],
)
single_version_override(
    module_name = "rules_go",
    version = "$RG",
    patch_strip = 1,
    patches = ["//toolchain_local:rules_go-pr4711.patch"],
)
single_version_override(
    module_name = "abseil-cpp",
    patch_strip = 1,
    patches = ["//toolchain_local:abseil-dragonfly.patch"],
)
go_sdk = use_extension("@rules_go//go:extensions.bzl", "go_sdk")
go_sdk.host(name = "go_default_sdk")
MOD
	# 煙試験は dist の外の workspace なので、そこでは rules_java の当て物だけを
	# 差す (下の RJ_PATCH の道)。host の go は GOROOT で教える
	EXTRA_BAZEL_ARGS="${EXTRA_BAZEL_ARGS:-} --repo_env=GOROOT=$(go env GOROOT 2>/dev/null || echo /usr/pkg/go126)"
	;;
esac

# MidnightBSD は __FreeBSD__ も定義する FreeBSD 派生で、JDK は FreeBSD 向けの
# build (include/freebsd)。uname -s だけが違うので、綴りを知る箇所を一つずつ
# 教えて、次にどこで止まるかを見る。
case "$OS" in
MidnightBSD)
	echo "=== MidnightBSD: build_unix_jni.sh に腕を足す"
	patch -p1 -f -i "$CI_DIR/midnightbsd/build_unix_jni-midnightbsd.patch" </dev/null
	# os.name が "MidnightBSD" なので OS.java が UNKNOWN に落ち、Linux の
	# source と constraint が選ばれて unix_jni_linux.cc が sys/xattr.h を
	# 探して落ちる (run 35736537908)。FreeBSD 派生なので FreeBSD と答えさせる
	patch -p1 -f -i "$CI_DIR/midnightbsd/os-midnightbsd.patch" </dev/null
	# rules_cc の cc_configure は os.name "midnightbsd" を BSD と知らず、gcc を
	# 探して "Cannot find gcc or CC" で落ちる (run 35692632379)。MidnightBSD の
	# C driver は cc (clang) で gcc は無い。CC で教える (rules_cc #862 の BSD の
	# 判定に midnightbsd は無い)。
	EXTRA_BAZEL_ARGS="${EXTRA_BAZEL_ARGS:-} --repo_env=CC=cc"
	# clang は module map を持つので cc_configure が layering_check を立て、
	# grpc がその検査に通らない (wait_for_single_owner.h が absl を export して
	# いないと言って落ちる、run 35741255342)。macOS で既にしているのと同じく、
	# 踏み台を建てる間だけ切る
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --features=-layering_check"
	# host platform の os 制約は platforms の extension が os.name から決める。
	# "midnightbsd" はどれにも当たらず制約無しになり、select が全部 linux の
	# 既定へ落ちる (run 35745771678)。freebsd と答えさせる
	mkdir -p toolchain_local
	cp "$CI_DIR/midnightbsd/platforms-midnightbsd.patch" toolchain_local/
	printf 'exports_files(glob(["*.patch"]))\n' > toolchain_local/BUILD
	cat >> MODULE.bazel <<MOD

# MidnightBSD is a FreeBSD derivative the host detection does not know (CI only).
single_version_override(
    module_name = "platforms",
    patch_strip = 1,
    patches = ["//toolchain_local:platforms-midnightbsd.patch"],
)
MOD
	# 次の壁は rules_go (run 35676218786)。JVM の os.name "midnightbsd" を
	# そのまま GOOS にするが、Go に MidnightBSD の port は無く、mports の go は
	# FreeBSD の build。rules_go に midnightbsd → freebsd の一行を差す。
	RG=$(grep -o 'name = "rules_go", version = "[^"]*"' MODULE.bazel | sed 's/.*version = "//; s/"//')
	mkdir -p toolchain_local
	cp "$CI_DIR/midnightbsd/rules_go-midnightbsd.patch" toolchain_local/
	printf 'exports_files(glob(["*.patch"]))\n' > toolchain_local/BUILD
	cat >> MODULE.bazel <<MOD

# MidnightBSD is not a GOOS; use the freebsd SDK (CI only).
single_version_override(
    module_name = "rules_go",
    version = "$RG",
    patch_strip = 1,
    patches = ["//toolchain_local:rules_go-midnightbsd.patch"],
)
MOD
	;;
esac

# OS ごとの手当て。どれも sh 化とは無関係で、素の dist を bash で建てるときにも要る物。
EXTRA_BAZEL_ARGS="${EXTRA_BAZEL_ARGS:-} --shell_executable=$SH_BIN"
case "$OS" in
Darwin)
	# clang の module map で grpc が layering_check に落ちる
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --features=-layering_check" ;;
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|OpenBSD|NetBSD|DragonFly)
	# libm は別 library。FreeBSD の devel/bazel9 も同じ
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --host_linkopt=-lm --linkopt=-lm"
	ulimit -n unlimited 2>/dev/null || ulimit -n 4096 2>/dev/null || true
	ulimit -d unlimited 2>/dev/null || true ;;
esac
case "$OS" in
MINGW*|MSYS*|CYGWIN*)
	# exec 構成の genrule (fastutil の zip) に client の PATH を届ける。
	# 9.3.0 の Windows の job と同じ。
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --host_action_env=PATH"
	# ARM64 の Windows では build_windows_jni.sh が amd64 の cl を呼んで、出来た
	# DLL を ARM64 の JVM が拒む (run 35692632379)。machine の native tools を選ぶ
	if [ "${PROCESSOR_ARCHITECTURE:-}" = ARM64 ]; then
		patch -p1 -f -i "$CI_DIR/build_windows_jni-arm64.patch" </dev/null
	fi ;;
esac
# Chimera は clang だけで gcc を持たない。rules_cc の cc_configure は gcc を
# 探して落ちる (run 35741255342)。CC で教える
# ID は引用符付きのこともある (ID="chimera") ので grep ではなく読んだ値で見る
if [ "$OS" = Linux ] && [ -f /etc/os-release ]; then
	DISTRO_ID=$(. /etc/os-release 2>/dev/null; echo "${ID:-}")
	if [ "$DISTRO_ID" = chimera ]; then
		EXTRA_BAZEL_ARGS="${EXTRA_BAZEL_ARGS:-} --repo_env=CC=clang"
	fi
fi
if [ "$OS" = OpenBSD ]; then
	# C++ の object を C の driver で link するので runtime を明示する
	for l in -lc++ -lc++abi -lpthread; do
		EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --host_linkopt=$l --linkopt=$l"
	done
fi
# master の bazel は incompatible_no_implicit_file_export が既定 true で、
# rules_python 1.7.0 は runtime_env_toolchain_interpreter.sh を export して
# いないので、bootstrap.sh が渡す --extra_toolchains=@rules_python//... で
# analysis が落ちる。検査を切るのではなく、rules_python にその一行 (main には
# 既に在る) を当てる。#30914 (rules_python の bump) が入れば要らなくなる。
if [ "$NO_VIS" = 1 ]; then
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --check_visibility=false"
elif [ -n "${RP_BUMP:-}" ]; then
	# 当て物ではなく、export を持つ版 (2.0.0 以降) へ上げる。上流の #30914 と同じ
	# 向き。2.x の互換性の変更に bazel の tree が耐えるかは、これで測る。
	cat >> MODULE.bazel <<MOD

# rules_python bumped past the missing exports_files (CI only; bazel#30914 does the same).
single_version_override(
    module_name = "rules_python",
    version = "$RP_BUMP",
)
MOD
	echo "rules_python を $RP_BUMP に上げた (当て物なし)"
else
	RP=$(grep -o 'name = "rules_python", version = "[^"]*"' MODULE.bazel | sed 's/.*version = "//; s/"//')
	[ -f "$CI_DIR/rules_python-$RP-export.patch" ] || { echo "rules_python $RP 向けの export の当て物が無い"; exit 1; }
	mkdir -p toolchain_local
	cp "$CI_DIR/rules_python-$RP-export.patch" toolchain_local/rules_python-export.patch
	[ -f toolchain_local/BUILD ] || printf 'exports_files(glob(["*.patch"]))\n' > toolchain_local/BUILD
	cat >> MODULE.bazel <<MOD

# rules_python $RP does not export runtime_env_toolchain_interpreter.sh (CI only;
# main does, and bazel#30914 bumps past it).
single_version_override(
    module_name = "rules_python",
    version = "$RP",
    patch_strip = 1,
    patches = ["//toolchain_local:rules_python-export.patch"],
)
MOD
	echo "rules_python $RP に export の一行を当てた (--check_visibility は既定のまま)"
fi
export EXTRA_BAZEL_ARGS
echo "EXTRA_BAZEL_ARGS=$EXTRA_BAZEL_ARGS"

BASHLOG=""
if [ "$LOG_BASH" = 1 ]; then
	BASHLOG=$WORK/bash-calls.log; : > "$BASHLOG"
	BASH_REAL=$(command -v bash || true)
	if [ -z "$BASH_REAL" ]; then
		echo "bash が無い箱なので記録は要らない"
	elif [ /bin/sh -ef "$BASH_REAL" ] || [ "$(readlink -f /bin/sh 2>/dev/null)" = "$(readlink -f "$BASH_REAL" 2>/dev/null)" ]; then
		# Fedora や Arch は /bin/sh が bash への symlink。bash を動かすと sh 自身が
		# 消えて何も動かなくなる (run 35611323359 で "sh: command not found")。
		# この箱では sh で走らせることと bash で走らせることが同じ物なので、
		# 数える意味も無い。
		echo "/bin/sh が bash そのもの ($BASH_REAL) なので記録 wrapper は張らない"
		BASHLOG=""
	else
		SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo
		$SUDO mv "$BASH_REAL" "$BASH_REAL.real"
		$SUDO sh -c "cat > '$BASH_REAL'" <<WRAP
#!/bin/sh
printf 'ppid=%s cwd=%s args=%s\\n' "\$PPID" "\$PWD" "\$*" >> "$BASHLOG"
exec "$BASH_REAL.real" "\$@"
WRAP
		$SUDO chmod 755 "$BASH_REAL"
		echo "$BASH_REAL を記録 wrapper にした"
	fi
fi

echo "=== bootstrap を $SH_BIN で"
"$SH_BIN" ./compile.sh > compile.log 2>&1 || true
BZ=output/bazel
if [ -x output/bazel.exe ]; then BZ=output/bazel.exe; fi
if [ -x "$BZ" ] && "$BZ" version 2>/dev/null | grep -q '^Build label:'; then
	"$BZ" version | grep 'Build label'
	echo "RESULT master-sh $OS $SH_BIN OK: 枝の dist を sh だけで bootstrap できた"
else
	echo "RESULT master-sh $OS $SH_BIN NG"
	# compile.sh が binary を作ったのに version が答えないことがある
	# (DragonFly、run 35793514425)。判定は stderr を捨てているので、ここで
	# 素の出力を見せる。出来ていないのか、出来たが動かないのかは別の話
	if [ -x "$BZ" ]; then
		echo "--- $BZ は在る。version をそのまま走らせる"
		"$BZ" version 2>&1 | head -20 || true
		# host_platform が無いと言われたとき (DragonFly、run 35806669764)、
		# 埋め込まれた bazel_tools の tools/BUILD が BUILD.tools の方だったか
		# 素の tools/BUILD の方だったかで答が決まる。create_embedded_tools.py
		# は同じ dir に両方在れば後者を捨てるので、捨て損なっていれば
		# host_platform を宣言していない BUILD が入っている。
		echo "--- 埋め込まれた bazel_tools の tools/BUILD"
		find "${BAZEL_WRKDIR:-/var/tmp}" -path '*external/bazel_tools/tools/BUILD' 2>/dev/null | while read -r b; do
			echo "$b: host_platform $(grep -c host_platform "$b") 行 / 全 $(wc -l < "$b") 行"
			head -12 "$b"
		done
		echo "--- 木の tools/BUILD.tools は在るか"
		ls -l tools/BUILD.tools tools/BUILD 2>&1 | head
	else
		echo "--- $BZ が無い"
	fi
	grep -n 'error\|ERROR\|not found\|Syntax\|syntax\|Bad substitution\|Bad fd\|unexpected' compile.log | tail -20
	tail -40 compile.log
	# JVM が落ちたなら hs_err の頭 (どの frame、どの命令) を残す。VM は job と
	# 一緒に消えるので、log に無ければ二度と読めない。
	# rules_java の当て物が効いていないように見えるとき (run 35692632379 の
	# NetBSD: jni_md_header-netbsd が無いと言われた) に、override が MODULE に
	# 在るか、取って来た rules_java に当たっているかを並べる。
	echo "--- MODULE.bazel の rules_java の override (末尾に足した分)"
	grep -n -B2 -A6 'module_name = "rules_java"' MODULE.bazel
	echo "--- toolchain_local"; ls -l toolchain_local 2>&1 | head
	echo "--- 取って来た rules_java に当たっているか"
	find / -maxdepth 6 -type d -name 'rules_java+' -path '*external*' 2>/dev/null | while read d; do
		[ -f "$d/toolchains/BUILD" ] || continue
		echo "$d: netbsd $(grep -c netbsd "$d/toolchains/BUILD") 行"
	done
	for h in hs_err_pid*.log; do
		[ -f "$h" ] || continue
		echo "--- $h"; sed -n '1,40p' "$h"
		grep -n -A8 '^Instructions:' "$h" | head -12
	done
	exit 1
fi

if [ -n "$BASHLOG" ]; then
	n=$(wc -l < "$BASHLOG" | tr -d ' ')
	echo "=== bootstrap の間に bash を呼んだ回数: $n"
	sed 's/^ppid=[0-9]* cwd=[^ ]* args=//' "$BASHLOG" | awk '{print $1, $2}' | sort | uniq -c | sort -rn | head -20
	echo "RESULT bash-calls $OS $n"
fi

echo "=== 煙試験"
# 煙試験は dist の外の workspace なので、module の解決で BCR を引きに行く
# (bootstrap の方は dist の repository_cache で足りている)。NetBSD の VM では
# そこが "No route to host" になった (run 35763299274)。箱に network が在るのか、
# bazel の JVM だけが届かないのかを分けるために、先に素の取得で確かめる。
if command -v ftp >/dev/null 2>&1; then
	ftp -o /dev/null "https://bcr.bazel.build/bazel_registry.json" 2>&1 | tail -2 \
		&& echo "BCR へは ftp(1) で届く" || echo "BCR へ ftp(1) でも届かない"
elif command -v curl >/dev/null 2>&1; then
	curl -fsS -o /dev/null "https://bcr.bazel.build/bazel_registry.json" \
		&& echo "BCR へは curl で届く" || echo "BCR へ curl でも届かない"
fi
case "$OS" in
MINGW*|MSYS*|CYGWIN*)
	# MSYS は //p:gen を /p:gen に path 変換して "invalid package name" になる。
	# label を変換の対象から外す。
	# '*' だと --repository_cache= の path 変換まで止まって bazel が動かない。
	# label だけを外す。
	MSYS2_ARG_CONV_EXCL='//'; export MSYS2_ARG_CONV_EXCL ;;
esac
mkdir -p "$WORK/smoke/p"; cd "$WORK/smoke"
RJ=$(grep -o 'name = "rules_java", version = "[^"]*"' "$WORK/dist/MODULE.bazel" | sed 's/.*version = "//; s/"//')
RC=$(grep -o 'name = "rules_cc", version = "[^"]*"' "$WORK/dist/MODULE.bazel" | sed 's/.*version = "//; s/"//')
printf 'bazel_dep(name = "rules_cc", version = "%s")\nbazel_dep(name = "rules_java", version = "%s")\n' "$RC" "$RJ" > MODULE.bazel
# rules_java の既定 toolchain は java_runtime に remotejdk_25 を決め打ちし、
# ijar / singlejar / turbine は linux_x86_64 なら glibc 向けの prebuilt を選ぶ。
# 遠隔 JDK の無い BSD と、prebuilt が動かない musl では、rules_java に当て物を
# 差して既定 toolchain を local の JDK と source 建ての道具に向ける。glibc の
# Linux と macOS と Windows は素の rules_java のまま (そこは素で通る)。
RJ_PATCH=""
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|OpenBSD|NetBSD|DragonFly) RJ_PATCH=1 ;;
Linux) if ls /lib/ld-musl-* >/dev/null 2>&1; then RJ_PATCH=1; fi ;;
esac
if [ -n "$RJ_PATCH" ]; then
	P="$CI_DIR/rules_java-$RJ-local.patch"
	[ -f "$P" ] || { echo "rules_java $RJ 向けの当て物 ($P) が無い"; exit 1; }
	cp "$P" rules_java-local.patch
	printf 'single_version_override(\n    module_name = "rules_java",\n    version = "%s",\n    patch_strip = 1,\n    patches = ["//:rules_java-local.patch"],\n)\n' "$RJ" >> MODULE.bazel
	: > BUILD
	echo "rules_java $RJ に当て物を差した"
	case "$OS" in
	NetBSD|DragonFly)
		# host の OS 検出 (platforms の _translate_os) も NetBSD を知らない
		cp "$CI_DIR/netbsd/platforms-pr142-pr143.patch" platforms-local.patch
		printf 'single_version_override(\n    module_name = "platforms",\n    patch_strip = 1,\n    patches = ["//:platforms-local.patch"],\n)\n' >> MODULE.bazel ;;
	esac
fi
cat > p/BUILD <<'B'
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_java//java:java_binary.bzl", "java_binary")
genrule(name = "gen", outs = ["gen.txt"], cmd = "echo genrule-ok > $@")
cc_binary(name = "hello_cc", srcs = ["hello.cc"])
java_binary(name = "hello_java", srcs = ["Hello.java"], main_class = "Hello")
B
printf '#include <cstdio>\nint main() { std::printf("cc-ok\\n"); return 0; }\n' > p/hello.cc
printf 'public class Hello { public static void main(String[] a) { System.out.println("java-ok"); } }\n' > p/Hello.java
# rules_java の遠隔 JDK と prebuilt (ijar, singlejar) は Linux glibc / macOS /
# Windows の分しか配られていない。BSD と musl では java_binary の煙試験は
# rules_java の platform 対応を測ることになり、この枝の話ではない。そこでは
# local の JDK を指して試し、落ちても報告に留めて job は落とさない。
JAVA_ARGS=""
case "$OS" in
FreeBSD|GhostBSD|HardenedBSD|MidnightBSD|OpenBSD|NetBSD|DragonFly) JAVA_ARGS="--java_runtime_version=local_jdk --tool_java_runtime_version=local_jdk" ;;
Linux) if [ -e /lib/ld-musl-x86_64.so.1 ]; then JAVA_ARGS="--java_runtime_version=local_jdk --tool_java_runtime_version=local_jdk"; fi ;;
esac
rc=0
for t in gen hello_cc hello_java; do
	if [ "$t" = gen ]; then act=build; else act=run; fi
	extra=""; if [ "$t" = hello_java ]; then extra=$JAVA_ARGS; fi
	# JVM が IPv6 を先に試して届かない箱があるので IPv4 を先にする
	if "$WORK/dist/$BZ" --host_jvm_args=-Djava.net.preferIPv4Stack=true $act --repository_cache="$WORK/dist/derived/repository_cache" ${EXTRA_BAZEL_ARGS:-} $extra "//p:$t" > "$WORK/smoke-$t.log" 2>&1; then
		echo "SMOKE //p:$t OK"
	else
		echo "SMOKE NG //p:$t"; tail -20 "$WORK/smoke-$t.log"; rc=1
	fi
done
if [ "$rc" = 0 ]; then echo "RESULT smoke $OS OK: genrule と cc と java が走った"; fi
exit $rc
