#!/bin/sh
# rules_java の java_binary 起動 stub を偽の JDK に向けて走らせ、JVM に渡った
# 引数・環境変数・classpath jar の manifest を、場合ごとに印字する。
#
#   compare.sh <template> <shell> <workdir>
#
# <shell> は "busybox sh" のように空白で区切ってよい。出力は元の bash の
# stub と POSIX の stub の間で diff するための物なので、走らせるたびに変わる
# 所 (作業 dir、mktemp の名前) は正規化する。
set -eu

unset CLASSPATH
tmpl=$1
shell=$2
w=$3

rm -rf "$w"
mkdir -p "$w/bin" "$w/out"
w=$(cd "$w" && pwd -P)

# 被試験の shell を一語で呼べるようにする
printf '#!/bin/sh\nexec %s "$@"\n' "$shell" >"$w/sut"
chmod +x "$w/sut"
shell=$w/sut

# 頼まれたことを印字するだけの JDK
mkdir -p "$w/jdk/bin"
cat >"$w/jdk/bin/java" <<'EOF'
#!/bin/sh
printf 'java'
for a; do printf ' [%s]' "$a"; done
printf '\n'
for v in JAVA_RUNFILES TEST_SRCDIR RUNFILES_MANIFEST_FILE \
    RUNFILES_MANIFEST_ONLY SELF_LOCATION CLASSLOADER_PREFIX_PATH \
    JACOCO_IS_JAR_WRAPPED CLASSPATH_JAR; do
  eval "printf '  %s=%s\n' $v \"\${$v-<unset>}\""
done
case "${2-}" in
  *.jar) [ -f "$2" ] && printf '  classpath jar exists\n' ;;
esac
exit 3
EOF
cat >"$w/jdk/bin/jar" <<'EOF'
#!/bin/sh
# jar cvfm <jar> <manifest>
sed "s/^/  | /" "$3" >&2
: >"$2"
EOF
chmod +x "$w/jdk/bin/java" "$w/jdk/bin/jar"

# bazel_java_binary.bzl と同じ置き換えで template から stub を作る
mkstub() {
  out=$1 manifest_only=$2 javabin=$3 classpath=$4
  sed -e "s|%runfiles_manifest_only%|$manifest_only|" \
      -e "s|%workspace_prefix%|_main/|" \
      -e "s|%javabin%|$javabin|" \
      -e "s|%needs_runfiles%|1|" \
      -e "s|%set_jacoco_metadata%||" \
      -e "s|%set_jacoco_main_class%||" \
      -e "s|%set_jacoco_java_runfiles_root%||" \
      -e "s|%java_start_class%|com.example.Main|" \
      -e "s|%jvm_flags%|-Dfoo=bar '-Dsp=a b'|" \
      -e "s|%classpath%|$classpath|" \
      "$tmpl" >"$out"
  chmod +x "$out"
}

# runfiles の木がある場合
mkstub "$w/bin/prog" "" \
  'JAVABIN=${JAVABIN:-${JAVA_RUNFILES}/jdk/bin/java}' \
  '"${RUNPATH}a.jar:${RUNPATH}dir with space/b.jar:${RUNPATH}'"$(printf 'u\303\274')"'%+.jar"'
mkdir -p "$w/bin/prog.runfiles/_main"
ln -s "$w/jdk" "$w/bin/prog.runfiles/jdk"
ln -s prog "$w/bin/link"

# MANIFEST だけの場合。CRLF の行と、値に空白を含む行を混ぜる
mkstub "$w/bin/mprog" 1 \
  'JAVABIN=${JAVABIN:-$(rlocation jdk/bin/java)}' \
  '"$(rlocation _main/a.jar):$(rlocation _main/b.jar):$(rlocation _main/c.jar)"'
mkdir -p "$w/bin/mprog.runfiles"
{
  printf 'jdk/bin/java %s\n' "$w/jdk/bin/java"
  printf '_main/a.jar /abs/a.jar\r\n'
  printf '_main/b.jar   /abs/dir  with/b.jar\n'
  printf '_main/c.jar /abs/c.jar\n'
} >"$w/bin/mprog.runfiles/MANIFEST"

i=0
run() {
  i=$((i + 1))
  printf '== %d:' "$i"
  for a; do
    [ "$a" = "$shell" ] || printf ' [%s]' "$a"
  done | sed "s|$w|@W@|g"
  printf '\n'
  set +e
  ( cd "$w" && LC_ALL=C JARBIN="$w/jdk/bin/jar" "$@" ) >"$w/out/log" 2>&1
  rc=$?
  set -e
  sed -e "s|$w|@W@|g" \
      -e 's|/[^] ]*/[A-Za-z0-9]*-classpath\.jar[.A-Za-z0-9]*|@TMPJAR@|g' \
      -e 's|=[A-Za-z0-9]*-classpath\.jar[.A-Za-z0-9]*|=@TMPJAR@|g' \
      -e 's|^[^ ]*prog: |@0@: |' \
      -e 's|^[^ ]*link: |@0@: |' \
      "$w/out/log"
  printf '   rc=%s\n' "$rc"
}

run "$shell" bin/prog
run "$shell" bin/prog a 'b c' '' "d'e" '*' '$HOME' 'x"y'
run "$shell" bin/prog --jvm_flag='-Da=b c' --jvm_flags='-X1 -X2' --jvm_flag="-Dq='q'" arg
run "$shell" bin/prog --debug --main_advice=Adv --main_advice_classpath=/m arg
run "$shell" bin/prog --debug=9 arg --debug --wrapper_script_flag=--jvm_flag=-Dw
run "$shell" bin/prog '' --debug
run "$shell" bin/prog --wrapper_script_flag=--bogus
run "$shell" bin/prog --singlejar arg
run "$shell" bin/prog --print_javabin
run "$shell" bin/prog --classpath_limit=x arg
run "$shell" bin/prog --classpath_limit=10 arg
run "$shell" "$w/bin/link" arg
run "$shell" bin/prog.runfiles/../prog arg
run env TEST_TMPDIR="$w/out" "$shell" bin/prog arg
run env JAVA_RUNFILES="$w/bin/prog.runfiles" "$shell" bin/prog arg
run "$shell" bin/mprog arg
run "$shell" bin/mprog --classpath_limit=10 arg
run env LC_ALL=en_US.UTF-8 "$shell" bin/prog --classpath_limit=10 arg
