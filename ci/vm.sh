#!/bin/bash
#
# ホスト側から NetBSD/i386 の VM を扱うための小道具。
# 実行するものではなく source して使う。
#
# 本番は ubuntu runner だが、手元の macOS でも同じ手順を踏めるようにして
# ある。違いは加速方式と vCPU 数の数え方だけ。

vm_accel() {
	if [ -w /dev/kvm ]; then
		# Linux/x86_64 ホスト。i386 ゲストはほぼ素の速さ。
		echo kvm
	elif [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = x86_64 ]; then
		echo hvf
	else
		# Apple Silicon はここ。HVF は arm64 ゲストにしか効かないので、
		# i386 は TCG (エミュレーション) になる。
		echo tcg
	fi
}

# macOS の tar は全ファイルに com.apple.provenance を書き込む。NetBSD 側で
# 展開すると一件ごとに "Cannot restore extended attributes" を吐いた上に
# 終了ステータスまで非ゼロになるので、作る側で入れない。
tar_noxattr() {
	if tar --no-xattrs --version >/dev/null 2>&1; then
		COPYFILE_DISABLE=1 tar --no-xattrs "$@"
	else
		COPYFILE_DISABLE=1 tar "$@"
	fi
}

vm_ncpu() {
	if command -v nproc >/dev/null 2>&1; then
		nproc
	else
		sysctl -n hw.ncpu 2>/dev/null || echo 2
	fi
}

# i386 ゲストを動かす qemu を探す。
#
# Debian 系は qemu-system-i386 を置くが、RHEL 系 (AlmaLinux, Rocky) には
# その名前が無く、qemu-kvm という名前で qemu-system-x86_64 が入る。
# x86_64 の qemu は 32bit ゲストをそのまま動かせるので、あるものを使う。
vm_qemu() {
	if [ -n "${VM_QEMU:-}" ]; then
		echo "$VM_QEMU"
		return
	fi
	for q in qemu-system-i386 qemu-system-x86_64 \
	         /usr/libexec/qemu-kvm /usr/bin/qemu-kvm; do
		if command -v "$q" >/dev/null 2>&1; then
			echo "$q"
			return
		fi
	done
	echo "!! i386 ゲストを動かせる qemu が見つからない" >&2
	echo "   Debian 系: qemu-system-x86  RHEL 系: qemu-kvm" >&2
	return 1
}

# install 用 ISO を焼く道具があるか見る。anita は genisoimage があれば
# それを、無ければ mkisofs を呼ぶ。RHEL 系は EL8.10 以降 genisoimage を
# 廃止していて、代わりに xorriso が mkisofs という名前も提供する。
vm_check_mkisofs() {
	command -v genisoimage >/dev/null 2>&1 && return 0
	command -v mkisofs >/dev/null 2>&1 && return 0
	echo "!! ISO を焼く道具が無い。anita が \"could not run mkisofs\" で落ちる。" >&2
	echo "   Debian 系: genisoimage  RHEL 系: xorriso  macOS: brew install cdrtools" >&2
	return 1
}

VM_DIR=${VM_DIR:-vm}
VM_IMAGE=${VM_IMAGE:-$VM_DIR/run.qcow2}
VM_FORMAT=${VM_FORMAT:-qcow2}
VM_MEM=${VM_MEM:-3072}
VM_CPUS=${VM_CPUS:-$(vm_ncpu)}
VM_SSH_PORT=${VM_SSH_PORT:-2222}

# TCG は vCPU を増やしても頭打ちになり、増やしすぎるとむしろ遅い。
if [ "$(vm_accel)" = tcg ] && [ "$VM_CPUS" -gt 4 ]; then
	VM_CPUS=4
fi

# ゲストは qemu の user networking 越しにホストを 10.0.2.2 として見る。
# 大きいものをホストからゲストへ渡すのはこの HTTP サーバ経由が一番速い。
# ポートはゲストの /etc/rc.d/ci_seed に焼き込んであるので変えられない。
SEED_PORT=${SEED_PORT:-8123}
SEED_DIR=${SEED_DIR:-seed}

seed_start() {
	mkdir -p "$SEED_DIR" "$VM_DIR"
	# SEED_PORT はゲストの /etc/rc.d/ci_seed に焼き込んであって動かせない。
	# 同じ機械で二つ並行させると取り合いになり、後から来た方が黙って
	# 繋がらないまま進む。先に見て止める。
	if command -v lsof >/dev/null 2>&1 &&
	   lsof -nP -iTCP:"$SEED_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
		echo "!! ポート $SEED_PORT が既に使われている。" >&2
		echo "   別の VM 作業が走っていないか確認すること" >&2
		echo "   (SEED_PORT はゲストに焼き込んであるので変えられない)。" >&2
		return 1
	fi
	# GitHub Actions は run ごとに別のシェルなので、切り離しておかないと
	# 次のステップに入る前に道連れにされることがある。setsid は Linux に
	# しかないので、無ければ nohup だけで済ませる。
	if command -v setsid >/dev/null 2>&1; then
		setsid nohup python3 -m http.server "$SEED_PORT" --bind 0.0.0.0 \
			--directory "$SEED_DIR" >"$VM_DIR/seed-httpd.log" 2>&1 &
	else
		nohup python3 -m http.server "$SEED_PORT" --bind 0.0.0.0 \
			--directory "$SEED_DIR" >"$VM_DIR/seed-httpd.log" 2>&1 &
	fi
	echo $! >"$VM_DIR/seed.pid"
	sleep 1
	echo "seed: http://10.0.2.2:$SEED_PORT/ ($SEED_DIR)"
}

seed_stop() {
	[ -f "$VM_DIR/seed.pid" ] || return 0
	kill "$(cat "$VM_DIR/seed.pid")" 2>/dev/null || true
	rm -f "$VM_DIR/seed.pid"
}

vm_start() {
	local accel qemu
	accel=$(vm_accel)
	qemu=$(vm_qemu) || return 1
	echo "vm: $qemu accel=$accel cpus=$VM_CPUS mem=${VM_MEM}M"
	"$qemu" \
		-machine pc,accel="$accel" \
		-smp "$VM_CPUS" -m "$VM_MEM" \
		-drive file="$VM_IMAGE",format="$VM_FORMAT",if=ide,index=0,cache=unsafe \
		-netdev user,id=n0,hostfwd=tcp:127.0.0.1:"$VM_SSH_PORT"-:22 \
		-device e1000,netdev=n0 \
		-object rng-random,filename=/dev/urandom,id=rng0 \
		-device virtio-rng-pci,rng=rng0 \
		-display none \
		-serial "file:$VM_DIR/console.log" \
		-pidfile "$VM_DIR/qemu.pid" \
		-daemonize
}

vm_ssh() {
	ssh -p "$VM_SSH_PORT" \
		-i "$VM_DIR/id_ci" \
		-o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR \
		-o ConnectTimeout=10 \
		-o ServerAliveInterval=30 \
		root@127.0.0.1 "$@"
}

# ゲストが起動して ci_seed が鍵を置き終えるまで待つ。KVM ありなら 1 分、
# TCG なら数分かかる。
vm_wait_ssh() {
	local deadline=$((SECONDS + ${1:-600}))
	while [ "$SECONDS" -lt "$deadline" ]; do
		if vm_ssh true 2>/dev/null; then
			echo "vm: ssh が通った (${SECONDS}s)"
			return 0
		fi
		sleep 5
	done
	echo "vm: ssh が通らないまま時間切れ。コンソールの最後を出す:" >&2
	tail -n 60 "$VM_DIR/console.log" >&2 || true
	return 1
}

# 止めるのは自分が起こしたものだけ。pkill でパターンに当てると、同じ機械で
# 動いている別の qemu を巻き込む。$VM_DIR/qemu.pid だけを見る。
#
# ssh が通るなら shutdown -p で落とす。通らない (インストーラの途中など)
# ときは SIGTERM を送り、それでも駄目なら最後に SIGKILL。
vm_stop() {
	[ -f "$VM_DIR/qemu.pid" ] || return 0
	local pid deadline
	pid=$(cat "$VM_DIR/qemu.pid")

	if vm_ssh 'sync; sync; /sbin/shutdown -p now' >/dev/null 2>&1; then
		echo "vm: shutdown -p を送った"
	else
		echo "vm: ssh が通らないので SIGTERM で落とす"
		kill "$pid" 2>/dev/null || true
	fi

	deadline=$((SECONDS + 120))
	while [ "$SECONDS" -lt "$deadline" ] && kill -0 "$pid" 2>/dev/null; do
		sleep 2
	done
	if kill -0 "$pid" 2>/dev/null; then
		echo "vm: 落ちないので SIGKILL"
		kill -9 "$pid" 2>/dev/null || true
	fi
	rm -f "$VM_DIR/qemu.pid"
}

# 走らせるたびに使い捨ての鍵を作る。ゲストは起動のたびにこれを
# http://10.0.2.2:8123/authorized_keys から取りに来る。
vm_make_key() {
	rm -f "$VM_DIR/id_ci" "$VM_DIR/id_ci.pub"
	ssh-keygen -q -t ed25519 -N '' -C ci -f "$VM_DIR/id_ci"
	mkdir -p "$SEED_DIR"
	cp "$VM_DIR/id_ci.pub" "$SEED_DIR/authorized_keys"
}
