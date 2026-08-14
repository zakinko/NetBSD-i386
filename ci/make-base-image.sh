#!/bin/bash
#
# NetBSD/i386 のベースイメージを anita で作る。
#
# anita は sysinst の出力をシリアルコンソールから読んで答えを流し込む道具で、
# NetBSD 本家のテストでも使われている。i386 に対応しているのは事実上これだけ
# なので (vmactions/netbsd-vm は amd64/aarch64/riscv64/sparc64 のみ)、
# 32bit の箱向けにはこの経路になる。
#
# 入れ方に注意: PyPI の "anita" は同名の別物 (ポルトガル語の論理学ツール)。
# 本家は https://www.gson.org/netbsd/anita/download/ にある。
#
#	pip install pexpect \
#	    https://www.gson.org/netbsd/anita/download/anita-2.18.tar.gz
#
# ISO を焼く道具も要る。Linux なら genisoimage、macOS なら mkisofs
# (brew install cdrtools)。無いと "could not run mkisofs" で止まる。
# なお anita 2.18 の make_iso() は Darwin と FreeBSD の判定が
# sysname[0] == 'Darwin' と書かれていて (文字列の先頭一文字との比較なので
# 常に偽)、macOS でも hdiutil ではなく mkisofs の経路に落ちる。mkisofs を
# 入れておけば動くので、ここではそのままにしてある。
#
# できたイメージは vm/base.qcow2。actions/cache に載せて使い回すので、
# 普段の build ではこのスクリプトは走らない。

set -euo pipefail

cd "$(dirname "$0")/.."
. ci/vm.sh

NETBSD_RELEASE=${NETBSD_RELEASE:-11.0}
NETBSD_ARCH=${NETBSD_ARCH:-i386}
NETBSD_URL=${NETBSD_URL:-https://cdn.netbsd.org/pub/NetBSD/NetBSD-$NETBSD_RELEASE/$NETBSD_ARCH/}
VM_DISK=${VM_DISK:-40G}

# X は動かさないが、native な X11_TYPE で組む package が base の X ヘッダを
# 見に行くので xbase と xcomp は要る。games と tests は要らない。
# anita が set 名を知らないと言ってきたら、VM_SETS= を空にして --sets ごと
# 外せば既定 (全部) になる。
VM_SETS=${VM_SETS:-kern-GENERIC,modules,base,etc,comp,man,misc,text,xbase,xcomp,xetc}

if [ "$(vm_accel)" = tcg ]; then
	echo "!! 加速なし (TCG)。インストールだけで 1-2 時間かかる。" >&2
	echo "   Apple Silicon の場合、i386 ゲストではこれが正常。" >&2
fi

mkdir -p "$VM_DIR" "$SEED_DIR"
cp ci/guest-bootstrap.sh "$SEED_DIR/"
seed_start
trap seed_stop EXIT

echo "=== anita: $NETBSD_URL を入れる (disk=$VM_DISK sets=$VM_SETS)"

# --run の中身はコンソール tty 越しに打ち込まれるので短くしておく。
# 実際の仕込みは guest-bootstrap.sh 側。
#
# 先頭の dhcpcd は必須。anita は NIC を明示的に足さないので (anita.py の
# 該当行はコメントアウトされている) qemu の既定の NIC がぶら下がるだけで、
# 入れたばかりのシステムでは dhcpcd が動いていない。そのままだと
# 10.0.2.2 に届かず "Can't assign requested address" で落ちる。
# guest-bootstrap.sh が rc.conf に dhcpcd=YES を書くので、次回以降の
# 起動では自動で上がる。
args=(
	--workdir "$VM_DIR/anita"
	--disk-size "$VM_DISK"
	--memory-size "${VM_MEM}M"
	--persist
	--vmm-args "-accel $(vm_accel) -smp $VM_CPUS"
	--run "dhcpcd -w; ftp -o /tmp/bs.sh http://10.0.2.2:$SEED_PORT/guest-bootstrap.sh && sh /tmp/bs.sh"
)
[ -n "$VM_SETS" ] && args+=(--sets "$VM_SETS")

anita "${args[@]}" boot "$NETBSD_URL"

echo "=== できたディスクを qcow2 に固める"
qemu-img convert -O qcow2 -c "$VM_DIR/anita/wd0.img" "$VM_DIR/base.qcow2"
qemu-img info "$VM_DIR/base.qcow2"

# 元の raw は大きいだけなので捨てる。キャッシュに載るのは base.qcow2 だけ。
rm -rf "$VM_DIR/anita"
