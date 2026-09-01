#!/bin/sh
# 私が書いた mozc の当て物が、その OS の上で本当に成り立つかを測る。
#
# header を読んで書いたものと、その OS が実際に持っているものは別である。
# FreeBSD の xucred に cr_pid が在るのは 13 からで、OpenBSD の sockpeercred は
# 手元から header が取れなかった。当てずに、コンパイルが通るかで測る。
#
# 落ちた場合も答えの一つとして出す。「型が無い」と「測れていない」を
# 区別できるよう、失敗はコンパイラの出力ごと残す。
set -u
echo "########## $(uname -srm) ##########"
T=${TMPDIR:-/tmp}/ipcchk.$$
mkdir -p "$T"
cd "$T" || exit 1

try() {  # try <名前> <本体>
	name=$1; shift
	cat > t.c <<EOF
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#if defined(__FreeBSD__) || defined(__DragonFly__)
#include <sys/ucred.h>
#endif
#include <stddef.h>
#include <stdio.h>
#include <unistd.h>
int main(void) { $* ; return 0; }
EOF
	if cc -o t t.c > cc.log 2>&1; then
		printf "  %-34s 通る   %s\n" "$name" "$(./t 2>&1 | head -1)"
	else
		printf "  %-34s ★ 通らない\n" "$name"
		grep -m2 -E 'error|no member|undeclared' cc.log | sed 's/^/      /'
	fi
}

echo "--- sockaddr_un: sun_len の直しが要るか ---"
try "offsetof(sun_path)" \
	'struct sockaddr_un a; printf("offsetof=%zu sizeof(sun_family)=%zu", offsetof(struct sockaddr_un, sun_path), sizeof(a.sun_family))'

echo "--- peer 資格情報: どの型と定数が在るか ---"
try "LOCAL_PEEREID + unpcbid"   'struct unpcbid c; printf("unp_pid ok %d", (int)sizeof(c.unp_pid)); (void)LOCAL_PEEREID'
try "LOCAL_PEERCRED + xucred"   'struct xucred c; printf("xucred ok %d", (int)sizeof(c)); (void)LOCAL_PEERCRED'
try "xucred.cr_pid"             'struct xucred c; printf("cr_pid ok %d", (int)sizeof(c.cr_pid))'
try "XUCRED_VERSION"            'printf("XUCRED_VERSION=%d", XUCRED_VERSION)'
try "SO_PEERCRED + sockpeercred" 'struct sockpeercred c; printf("pid ok %d", (int)sizeof(c.pid)); (void)SO_PEERCRED'

echo "--- 実行可能ファイルの path を引く sysctl ---"
try "KERN_PROC_PATHNAME がある"  'printf("KERN_PROC_PATHNAME=%d", KERN_PROC_PATHNAME)'
# rc=0 だけでは足りない。NetBSD で FreeBSD 形の MIB を投げると rc=0 が返るが
# len=0 で中身はゴミである。「失敗した」ではなく「成功したように見えて空を
# 返す」ので、長さと中身まで見ないと、どちらの形が正しいかを取り違える。
try "KERN_PROC 経由 (FreeBSD 形)" \
	'int n[]={CTL_KERN,KERN_PROC,KERN_PROC_PATHNAME,(int)getpid()}; char b[1024]; size_t l=sizeof(b); b[0]=0; int r=sysctl(n,4,b,&l,NULL,0); printf("rc=%d len=%zu %s path=%s", r, l, (r==0 && l>1 && b[0]==0x2f) ? "USABLE" : "UNUSABLE", r==0?b:"-")'
try "KERN_PROC_ARGS 経由 (NetBSD 形)" \
	'int n[]={CTL_KERN,KERN_PROC_ARGS,(int)getpid(),KERN_PROC_PATHNAME}; char b[1024]; size_t l=sizeof(b); b[0]=0; int r=sysctl(n,4,b,&l,NULL,0); printf("rc=%d len=%zu %s path=%s", r, l, (r==0 && l>1 && b[0]==0x2f) ? "USABLE" : "UNUSABLE", r==0?b:"-")'

echo "--- log のスレッド ID ---"
try "pthread_getthreadid_np"  '(void)0; printf("skip")'
try "getthrid"               '(void)0; printf("skip")'

cd /; rm -rf "$T"
