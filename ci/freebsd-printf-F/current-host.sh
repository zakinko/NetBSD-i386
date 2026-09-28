#!/bin/sh
# FreeBSD 16.0-CURRENT の公式の VM 像を qemu (KVM) で起こし、boot.sh を
# 走らせて結果を読む。GitHub の Linux runner の上で動く。
set -eu
D=$(cd "$(dirname "$0")" && pwd)
W=${RUNNER_TEMP:-/tmp}/cur
mkdir -p "$W" && cd "$W"
B=https://download.freebsd.org/snapshots/VM-IMAGES/16.0-CURRENT/amd64/Latest
I=FreeBSD-16.0-CURRENT-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz

curl -fsSL -o "$I" "$B/$I"
curl -fsSL -o CHECKSUM.SHA256 "$B/CHECKSUM.SHA256"
# CHECKSUM の名前には日付・git の hash・revision が入る
# (…-BASIC-CLOUDINIT-20260928-36d3e711bc62-289650-ufs.qcow2.xz)。Latest/ の
# 名前には入らない。
L=$(grep -E 'BASIC-CLOUDINIT-[0-9]+-[0-9a-f]+-[0-9]+-ufs\.qcow2\.xz' CHECKSUM.SHA256)
[ "$(echo "$L" | wc -l)" = 1 ] || { echo "CHECKSUM の行が一つに決まらない"; echo "$L"; exit 1; }
echo "$L" | sed 's/.*= //' > want
echo "像の元: $(echo "$L" | sed 's/^SHA256 (//; s/).*//')"
H=$(echo "$L" | sed -n 's/.*BASIC-CLOUDINIT-[0-9]*-\([0-9a-f]*\)-[0-9]*-ufs.*/\1/p')
FULL=$(gh api "repos/freebsd/freebsd-src/commits/$H" -q .sha)
echo "像の commit: $H -> $FULL"
echo "$(sha256sum "$I" | cut -d' ' -f1)" > got
cmp want got || { echo "像の sha256 が合わない"; exit 1; }
echo "像: $I  sha256 $(cat got)"
xz -d "$I"
qemu-img resize -q "${I%.xz}" +20G

mkdir -p seed
printf 'instance-id: pf-%s\nlocal-hostname: pf\n' "$(date +%s)" > seed/meta-data
cat > seed/user-data <<'U'
#cloud-config
runcmd:
  - mkdir -p /var/tmp/pfin && mount_cd9660 /dev/iso9660/cidata /mnt && cp /mnt/*.patch /mnt/run-current.sh /mnt/boot.sh /mnt/commit /var/tmp/pfin/ && umount /mnt && sh /var/tmp/pfin/boot.sh
U
cp "$D"/0*.patch "$D/run-current.sh" "$D/boot.sh" seed/
echo "$FULL" > seed/commit
genisoimage -quiet -V cidata -J -r -o seed.iso seed

printf 'PFRESULTS\n' > res.img
truncate -s 8M res.img

sudo chmod 666 /dev/kvm
timeout 110m qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 8192 \
	-drive file="${I%.xz}",if=virtio,format=qcow2 \
	-drive file=seed.iso,if=virtio,format=raw,readonly=on \
	-drive file=res.img,if=virtio,format=raw \
	-netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
	-display none -serial file:console.log || echo "qemu rc=$?"

echo "######## 結果の disk"
tr -d '\000' < res.img > result.txt
if head -c 9 result.txt | grep -q PFRESULTS; then
	echo "結果が書かれていない (VM の中で boot.sh まで届いていない)"
	echo "######## console の末尾"; tail -60 console.log
	exit 1
fi
cat result.txt
grep -q '^RESULT OK' result.txt
