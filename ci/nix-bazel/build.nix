# nixpkgs の bazel_9 を source から建てる。nixpkgs が rules_java の起動 stub と
# rules_cc の generate_system_module_map.sh に当てている shebang の書き換え
# (third_party/rules_{java,cc}.patch) を、variant の当て物で置き換える。
#   ours     両方を POSIX sh にする当て物 (shebang は #!/bin/sh)
#   control  copyright の行だけ触る当て物 (shebang は #!/usr/bin/env bash のまま)
{ nixpkgsRev, ciDir, variant }:
let
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/${nixpkgsRev}.tar.gz") { };
in
pkgs.bazel_9.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp ${ciDir}/nix-bazel/rules_java-${variant}.diff third_party/rules_java.patch
    cp ${ciDir}/nix-bazel/rules_cc-${variant}.diff third_party/rules_cc.patch
    echo "VARIANT ${variant}: rules_java.patch の + 側の shebang: $(grep -m1 '^+#!' third_party/rules_java.patch || echo 変えない)"
  '';
})
