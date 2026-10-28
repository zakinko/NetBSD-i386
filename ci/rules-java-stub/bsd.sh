#!/bin/sh
# BSD の /bin/sh で POSIX の stub を走らせ、Linux の dash で走らせた結果
# (rules-java-stub.yml の linux job が残す t/new-dash.txt) と突き合わせる。
# 元の bash の stub は、bash の無い箱では基準にできないので Linux で取る。
set -u
cd "$GITHUB_WORKSPACE"
uname -sr
echo "/bin/sh: $(ls -l /bin/sh)"
command -v bash >/dev/null 2>&1 && echo "bash: $(command -v bash) (この試験では使わない)" || echo "bash: 無い"
sh ci/rules-java-stub/compare.sh t/new.txt /bin/sh /tmp/stubw > t/bsd.txt 2>&1
if diff t/new-dash.txt t/bsd.txt > t/bsd.diff; then
	echo "RESULT $(uname -s) /bin/sh: Linux の dash と一致"
else
	echo "RESULT $(uname -s) /bin/sh: 差 $(grep -c '^[<>]' t/bsd.diff) 行"; cat -v t/bsd.diff
fi
# shebang (#!/bin/sh) で直に起こしても動くか
/tmp/stubw/bin/prog arg >/dev/null 2>&1; rc=$?
echo "RESULT $(uname -s) shebang: rc=$rc (3 なら偽の java まで届いた)"
