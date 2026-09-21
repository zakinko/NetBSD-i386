#!/bin/sh
# 配布済みの bazel で、枝の checkout から dist archive を作る。dist は OS に
# 依らないので Linux で一度作れば、各 OS はそれを落として bootstrap すればよい。
#
# 使い方: make-master-dist.sh <出力先の zip>
#   REPO / BRANCH   枝 (既定 zakinko/bazel の posix-sh-v2)
#   BAZEL_VER       使う配布済み bazel の版 (既定 9.2.0)
set -eu
OUT=$1
REPO=${REPO:-https://github.com/zakinko/bazel.git}
BRANCH=${BRANCH:-posix-sh-v2}
BAZEL_VER=${BAZEL_VER:-9.2.0}
WORK=${WORK:-$PWD/make-dist-work}

"${JAVA_HOME:?}/bin/javac" -version
case "$(uname -sm)" in
"Linux x86_64")  ASSET=bazel-${BAZEL_VER}-linux-x86_64 ;;
"Darwin arm64")  ASSET=bazel-${BAZEL_VER}-darwin-arm64 ;;
*) echo "配布 binary の名前を知らない: $(uname -sm)"; exit 1 ;;
esac
rm -rf "$WORK"; mkdir -p "$WORK"
curl -fsSL -o "$WORK/bazel" "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VER}/${ASSET}"
chmod +x "$WORK/bazel"; "$WORK/bazel" version | grep 'Build label'
git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$WORK/src"
cd "$WORK/src"; echo "枝の先頭: $(git log --oneline -1)"
echo "--- 枝が触る file の shebang"
for f in compile.sh scripts/bootstrap/*.sh src/main/cpp/generate_jvm_module_options.sh \
         src/merge_zip_files.sh src/zip_files.sh src/package-bazel.sh tools/genrule/genrule-setup.sh; do
	printf '%-50s %s\n' "$f" "$(head -1 "$f")"
done
"$WORK/bazel" build //:bazel-distfile > "$WORK/distfile.log" 2>&1 \
	|| { echo "dist archive が作れない"; tail -40 "$WORK/distfile.log"; exit 1; }
cp bazel-bin/bazel-distfile.zip "$OUT"
"$WORK/bazel" shutdown >/dev/null 2>&1 || true
echo "dist: $OUT ($(du -h "$OUT" | cut -f1))  枝 $BRANCH $(git rev-parse --short HEAD)"
