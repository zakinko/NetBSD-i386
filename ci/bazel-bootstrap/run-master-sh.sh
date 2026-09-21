#!/bin/sh
# master (の枝) の bootstrap script と build 用 shell tool を POSIX sh 化した
# 変更を、枝そのもので踏む。
#
# 9.3.0 用の posix-sh.patch は 9.3.0 の dist にしか当たらず、master の枝は
# それとは別の変換なので、枝を実際に建てないと証拠にならない。
#
#   1. 配布済みの bazel で、枝の checkout から dist archive を作る
#      (bazel build //:bazel-distfile)。ここは何の shell でもよい
#   2. その dist を $SH_BIN で bootstrap する (compile.sh を sh で起動し、
#      genrule の shell も --shell_executable=$SH_BIN にする)
#   3. 出来た bazel で小さな workspace を建てて走らせる
#
# LOG_BASH=1 なら、/bin/bash を記録付きの wrapper に差し替えて、2 の間に
# 誰が bash を呼んだかを全部残す (root が要る。Ubuntu の runner 向け)。
# --shell_executable を通しても、script の shebang や env bash は残るので、
# 「bash を呼ばない」は wrapper で数えるまで言えない。
#
# 使い方: run-master-sh.sh
#   REPO / BRANCH   枝 (既定 zakinko/bazel の posix-sh-v2)
#   BAZEL_VER       1 で使う配布済み bazel の版 (既定 9.2.0)
#   SH_BIN          2 で使う shell (既定 /bin/sh)
#   LOG_BASH        1 なら bash の呼び出しを記録する
set -eu

REPO=${REPO:-https://github.com/zakinko/bazel.git}
BRANCH=${BRANCH:-posix-sh-v2}
BAZEL_VER=${BAZEL_VER:-9.2.0}
SH_BIN=${SH_BIN:-/bin/sh}
LOG_BASH=${LOG_BASH:-0}
WORK=${WORK:-$PWD/master-sh-work}

echo "=== JDK / OS / sh"
"${JAVA_HOME:?}/bin/javac" -version
uname -sm; "$SH_BIN" -c 'echo "sh は $0"'
case "$(uname -sm)" in
"Linux x86_64")  ASSET=bazel-${BAZEL_VER}-linux-x86_64 ;;
"Darwin arm64")  ASSET=bazel-${BAZEL_VER}-darwin-arm64 ;;
"Darwin x86_64") ASSET=bazel-${BAZEL_VER}-darwin-x86_64 ;;
*) echo "この箱向けの配布 binary の名前を知らない: $(uname -sm)"; exit 1 ;;
esac

rm -rf "$WORK"; mkdir -p "$WORK"
echo "=== 1. 配布済みの bazel $BAZEL_VER を取る"
curl -fsSL -o "$WORK/bazel" "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VER}/${ASSET}"
chmod +x "$WORK/bazel"; "$WORK/bazel" version | grep 'Build label'

echo "=== 1. 枝 $BRANCH を取って dist archive を作る"
git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$WORK/src"
cd "$WORK/src"; git log --oneline -3
echo "--- 枝が触る file の shebang"
for f in compile.sh scripts/bootstrap/*.sh src/main/cpp/generate_jvm_module_options.sh \
         src/merge_zip_files.sh src/zip_files.sh src/package-bazel.sh tools/genrule/genrule-setup.sh; do
	printf '%-50s %s\n' "$f" "$(head -1 "$f")"
done
EXTRA="${EXTRA_BAZEL_ARGS:-}"
case "$(uname -s)" in Darwin) EXTRA="$EXTRA --features=-layering_check" ;; esac
"$WORK/bazel" build $EXTRA //:bazel-distfile > "$WORK/distfile.log" 2>&1 \
	|| { echo "dist archive が作れない"; tail -40 "$WORK/distfile.log"; exit 1; }
DIST=$(ls bazel-bin/bazel-distfile.zip)
echo "dist: $DIST ($(du -h "$DIST" | cut -f1))"
"$WORK/bazel" shutdown >/dev/null 2>&1 || true

echo "=== 2. その dist を $SH_BIN で bootstrap する"
mkdir -p "$WORK/dist"; ( cd "$WORK/dist" && unzip -q "$OLDPWD/$DIST" )
cd "$WORK/dist"
for f in compile.sh scripts/bootstrap/compile.sh scripts/bootstrap/buildenv.sh scripts/bootstrap/bootstrap.sh; do
	head -1 "$f" | grep -q '^#!/bin/sh$' || { echo "$f の shebang が #!/bin/sh でない (dist に枝の変更が入っていない)"; exit 1; }
done

BASHLOG=""
if [ "$LOG_BASH" = 1 ]; then
	BASHLOG=$WORK/bash-calls.log; : > "$BASHLOG"
	# /bin/bash を wrapper にする。誰が何を渡して呼んだかを一行ずつ残して
	# 本物へ渡す。shebang の /bin/bash も env bash も PATH の bash も全部通る。
	sudo mv /bin/bash /bin/bash.real
	sudo tee /bin/bash >/dev/null <<WRAP
#!/bin/sh
printf 'ppid=%s cwd=%s args=%s\\n' "\$PPID" "\$PWD" "\$*" >> "$BASHLOG"
exec /bin/bash.real "\$@"
WRAP
	sudo chmod 755 /bin/bash
	echo "/bin/bash を記録 wrapper にした ($BASHLOG)"
fi

EXTRA_BAZEL_ARGS="${EXTRA_BAZEL_ARGS:-} --shell_executable=$SH_BIN"
# master の bazel が rules_python 1.7.0 の runtime_env_toolchain_interpreter.sh を
# visibility で弾く (9.3.0 の bazel は同じ 1.7.0 で通す)。sh 化とは無関係で、
# bash で bootstrap した対照でも同じ所で落ちることを別 job で確かめている。
# NO_VIS=1 のときだけ検査を切って、sh 化の script を analysis の先まで踏ませる。
if [ "${NO_VIS:-0}" = 1 ]; then
	EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --check_visibility=false"
fi
case "$(uname -s)" in Darwin) EXTRA_BAZEL_ARGS="$EXTRA_BAZEL_ARGS --features=-layering_check" ;; esac
export EXTRA_BAZEL_ARGS
"$SH_BIN" ./compile.sh > compile.log 2>&1 || true
if [ -x output/bazel ] && output/bazel version 2>/dev/null | grep -q '^Build label:'; then
	output/bazel version | grep 'Build label'
	echo "RESULT master-sh $(uname -s) $SH_BIN OK: 枝の dist を sh だけで bootstrap できた"
else
	echo "RESULT master-sh $(uname -s) $SH_BIN NG"
	grep -n 'error\|ERROR\|not found\|Syntax\|syntax\|Bad substitution\|unexpected' compile.log | tail -20
	tail -40 compile.log
	exit 1
fi

if [ -n "$BASHLOG" ]; then
	echo "=== 2. bootstrap の間に bash を呼んだもの: $(wc -l < "$BASHLOG") 回"
	# 呼び手ごとに丸めて数える。args の先頭 (何を実行したか) で分ける
	sed 's/^ppid=[0-9]* cwd=[^ ]* args=//' "$BASHLOG" | awk '{print $1, $2}' | sort | uniq -c | sort -rn | head -20
	echo "RESULT bash-calls $(wc -l < "$BASHLOG")"
fi

echo "=== 3. 出来た bazel で小さな workspace を建てて走らせる"
mkdir -p "$WORK/smoke/p"; cd "$WORK/smoke"
RJ=$(grep -o 'name = "rules_java", version = "[^"]*"' "$WORK/dist/MODULE.bazel" | sed 's/.*version = "//; s/"//')
RC=$(grep -o 'name = "rules_cc", version = "[^"]*"' "$WORK/dist/MODULE.bazel" | sed 's/.*version = "//; s/"//')
printf 'bazel_dep(name = "rules_cc", version = "%s")\nbazel_dep(name = "rules_java", version = "%s")\n' "$RC" "$RJ" > MODULE.bazel
cat > p/BUILD <<'B'
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_java//java:java_binary.bzl", "java_binary")
genrule(name = "gen", outs = ["gen.txt"], cmd = "echo genrule-ok > $@")
cc_binary(name = "hello_cc", srcs = ["hello.cc"])
java_binary(name = "hello_java", srcs = ["Hello.java"], main_class = "Hello")
B
printf '#include <cstdio>\nint main() { std::printf("cc-ok\\n"); return 0; }\n' > p/hello.cc
printf 'public class Hello { public static void main(String[] a) { System.out.println("java-ok"); } }\n' > p/Hello.java
rc=0
for t in gen hello_cc hello_java; do
	if [ "$t" = gen ]; then act=build; else act=run; fi
	if "$WORK/dist/output/bazel" $act --repository_cache="$WORK/dist/derived/repository_cache" ${EXTRA_BAZEL_ARGS:-} "//p:$t" > "$WORK/smoke-$t.log" 2>&1; then
		echo "SMOKE //p:$t OK"
	else
		echo "SMOKE NG //p:$t"; tail -20 "$WORK/smoke-$t.log"; rc=1
	fi
done
if [ "$rc" = 0 ]; then
	echo "RESULT smoke $(uname -s) OK: genrule と cc と java が走った"
fi
exit $rc
