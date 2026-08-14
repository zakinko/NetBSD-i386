#!/bin/bash
#
# 手元で CI と同じ手順を回す。ワークフローの「VM を起動する」から
# 「結果を取り出す」までに相当する。
#
#	ci/run-local.sh [pkglist]
#
# 前提:
#   - vm/base.qcow2 が ci/make-base-image.sh でできていること
#   - qemu と、anita を入れた venv が PATH にあること
#
# pkglist を省くとリポジトリの pkglist を使う。検証だけしたいときは小さい
# 一覧を渡す:
#
#	printf 'sysutils/augeas\ntextproc/libxml2\n' > /tmp/small
#	ci/run-local.sh /tmp/small
#
# Apple Silicon では i386 は TCG になるので、150 個を通すのは現実的でない。
# 配管と、数個のパッケージが本当に組めるかの確認に使うもの。

set -euo pipefail

cd "$(dirname "$0")/.."
. ci/vm.sh

ROLES=${1:-roles}
BUILD_DEADLINE_MIN=${BUILD_DEADLINE_MIN:-600}

die() { echo "!! $*" >&2; exit 1; }

[ -f "$VM_DIR/base.qcow2" ] || die "$VM_DIR/base.qcow2 がない。先に ci/make-base-image.sh を回すこと。"
[ -f "$ROLES" ] || die "$ROLES がない"
[ -d sbin ] || die "sbin/ がない。bin/nb-sync-sbin で写しを取ること。"
vm_qemu >/dev/null || die "i386 ゲストを動かせる qemu が無い"

cleanup() { vm_stop || true; seed_stop || true; }
trap cleanup EXIT

echo "=== 種を並べる ($SEED_DIR)"
mkdir -p "$SEED_DIR"
cp sbin/mk.conf ci/mk.conf.ci ci/guest-build.sh "$SEED_DIR/"
cp "$ROLES" "$SEED_DIR/roles"
tar_noxattr -czf "$SEED_DIR/sbin.tar.gz" sbin
echo "    roles: $(grep -cvE '^[[:space:]]*(#|$)' "$ROLES") 行"

# overlay は pkgsrc ツリーに焼き込まれて渡る (ci/make-pkgsrc-tarball.sh)。
# 実体は pkgsrc-zakinko の overlay/。ここでは何もしない。
rm -f "$SEED_DIR/overlay.tar.gz"

# 手元では前回分を使わない。毎回まっさらから確かめたいので。
rm -f "$SEED_DIR/prev-packages.tar"

[ -f "$SEED_DIR/pkgsrc.tar.gz" ] || ci/make-pkgsrc-tarball.sh

echo "=== VM を起こす"
vm_make_key
seed_start
rm -f "$VM_DIR/run.qcow2"
qemu-img create -q -f qcow2 -b "$PWD/$VM_DIR/base.qcow2" -F qcow2 \
                "$VM_DIR/run.qcow2" 40G 2>/dev/null ||
qemu-img create -q -f qcow2 -b "$VM_DIR/base.qcow2" -F qcow2 \
                "$VM_DIR/run.qcow2" 40G
vm_start
vm_wait_ssh 1800
vm_ssh 'uname -a; df -h /'

echo "=== ビルド"
vm_ssh 'ftp -o /root/guest-build.sh http://10.0.2.2:8123/guest-build.sh'
vm_ssh "BUILD_DEADLINE_MIN=$BUILD_DEADLINE_MIN sh /root/guest-build.sh 2>&1" |
	tee "$VM_DIR/build.log"

echo "=== 結果を取り出す"
rm -rf packages && mkdir -p packages
vm_ssh 'cd /usr/pkgsrc/packages && tar cf - All' | tar xf - -C packages
vm_ssh 'cat /tmp/ci-report' | tee "$VM_DIR/report.txt"
vm_ssh 'cat /tmp/failed' >"$VM_DIR/failed.txt" 2>/dev/null || true
vm_ssh 'cat /tmp/tested' >"$VM_DIR/tested.txt" 2>/dev/null || true

echo
echo "=== できたもの"
ls -lh packages/All | head -20
[ -s "$VM_DIR/failed.txt" ] && { echo "=== 作れなかったもの"; cat "$VM_DIR/failed.txt"; }
[ -s "$VM_DIR/tested.txt" ] && { echo "=== 当て物の make test"; cat "$VM_DIR/tested.txt"; }
exit 0
