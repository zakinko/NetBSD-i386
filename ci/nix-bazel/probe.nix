# Nix の build sandbox の中で、/bin/sh と /usr/bin/env の有無を見て、
# 元の (bash の) 起動 stub と POSIX sh の stub を shebang から起こす。
# PATH は二通り: bazel が空にしたとき (nixpkgs の bash の wrapper が見る
# /no-such-path) と、nixpkgs の bazel が action に渡す道具の PATH。
{ nixpkgsRev, ciDir }:
let
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/${nixpkgsRev}.tar.gz") { };
  utilsPath = pkgs.lib.makeBinPath (with pkgs; [ coreutils diffutils file findutils gawk gnugrep gnupatch gnused ]);
in
pkgs.runCommand "stub-probe" { inherit ciDir utilsPath; } ''
  set +e
  mkdir -p $out
  {
    echo "PROBE|/bin/sh|$(ls -l /bin/sh 2>&1)"
    echo "PROBE|/bin/sh real|$(readlink -f /bin/sh 2>&1)"
    [ -e /usr/bin/env ] && echo "PROBE|/usr/bin/env|ある" || echo "PROBE|/usr/bin/env|無い"
    for p in /no-such-path "$utilsPath"; do
      tag=empty; [ "$p" = /no-such-path ] || tag=utils
      miss=$(env -i PATH="$p" /bin/sh -c 'for t in awk od sed readlink dirname uname; do command -v $t >/dev/null 2>&1 || printf "%s " $t; done')
      echo "PROBE|PATH=$tag で見えない道具|''${miss:-無し}"
    done
    for v in orig new; do
      w=$TMPDIR/w-$v
      sh $ciDir/rules-java-stub/compare.sh $ciDir/nix-bazel/stub-$v.txt sh $w >/dev/null 2>&1
      for p in /no-such-path "$utilsPath"; do
        tag=empty; [ "$p" = /no-such-path ] || tag=utils
        o=$(env -i PATH="$p" $w/bin/prog arg 2>&1); rc=$?
        echo "PROBE|stub $v PATH=$tag|rc=$rc|$(echo "$o" | head -1 | cut -c1-140)"
      done
    done
  } | tee $out/result
''
