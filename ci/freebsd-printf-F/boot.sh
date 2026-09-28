#!/bin/sh
# seed から写した後、cloud-init の runcmd が root で呼ぶ。測って、結果を
# 専用の disk (先頭に PFRESULTS と書いてある物) に書き、電源を切る。
# serial console が出るかどうかに頼らないため、結果は disk で返す。
sh /var/tmp/pfin/run-current.sh /var/tmp/pfin
for d in /dev/vtbd[0-9]; do
	if dd if="$d" bs=512 count=1 2>/dev/null | head -c 9 | grep -q PFRESULTS; then
		dd if=/var/tmp/result.txt of="$d" bs=512 conv=sync 2>/dev/null
		echo "結果を $d に書いた" >/dev/console
	fi
done
shutdown -p now
