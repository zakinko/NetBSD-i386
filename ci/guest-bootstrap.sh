#!/bin/sh
#
# anita が入れたばかりの NetBSD/i386 を、CI から ssh で叩ける状態にする。
# ベースイメージを作るときに一度だけ、anita の --run から実行される。
# ここでやったことはイメージに焼かれ、以後のビルドはこの状態から始まる。

set -eu

echo "=== ci: bootstrap 開始"

# pkgsrc の distfile は今どき大半が https なので、base の信頼アンカーを
# 使える形に展開しておく。sysinst が済ませていることもあるが二度やっても
# 害はない。
certctl rehash || echo "ci: certctl rehash に失敗 (無視して続行)"

# 起動のたびにホストから ssh 公開鍵を取ってくる rc.d スクリプト。
# 鍵は走らせるたびに作り直されるので、イメージ側に焼くわけにはいかない。
# 10.0.2.2 は qemu の user networking から見たホスト、8123 は
# ci/vm.sh の SEED_PORT。片方を変えるならもう片方も変えること。
cat >/etc/rc.d/ci_seed <<'EOF'
#!/bin/sh
#
# PROVIDE: ci_seed
# REQUIRE: NETWORKING
# BEFORE: sshd

$_rc_subr_loaded . /etc/rc.subr

name="ci_seed"
start_cmd="ci_seed_start"
stop_cmd=":"

ci_seed_start()
{
	mkdir -p /root/.ssh
	chmod 700 /root/.ssh

	i=0
	while [ $i -lt 90 ]; do
		if ftp -o /root/.ssh/authorized_keys \
		    http://10.0.2.2:8123/authorized_keys; then
			chmod 600 /root/.ssh/authorized_keys
			echo "ci_seed: authorized_keys を置いた"
			return 0
		fi
		sleep 2
		i=$((i + 1))
	done
	echo "ci_seed: ホストから鍵を取れなかった" >&2
	return 1
}

load_rc_config $name
run_rc_command "$1"
EOF
chmod 755 /etc/rc.d/ci_seed

cat >>/etc/rc.conf <<'EOF'

# CI 用
dhcpcd=YES
sshd=YES
ci_seed=YES
EOF

# 鍵でだけ root を通す。この VM は runner の 127.0.0.1 にしか出ていない。
cat >>/etc/ssh/sshd_config <<'EOF'

# CI 用
PermitRootLogin prohibit-password
PasswordAuthentication no
UseDNS no
EOF

mkdir -p /usr/pkgsrc

sync
echo "=== ci: bootstrap 完了"
