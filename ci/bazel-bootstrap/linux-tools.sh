#!/bin/sh
# Linux の container に、bazel の bootstrap に要る道具を入れる。distro は
# /etc/os-release で見分ける。musl の箱では temurin (glibc 向け) が動かないので
# distro の JDK を入れ、JAVA_HOME と (25 が無ければ) JAVA_VERSION を GITHUB_ENV へ書く。
# glibc の箱は JDK を入れず、あとの setup-java (temurin 25) に任せる。
set -eu
. /etc/os-release
echo "### distro: $ID $VERSION_ID  /bin/sh -> $(readlink -f /bin/sh)  musl: $(ls /lib/ld-musl-* 2>/dev/null || echo no)"
case "$ID" in
alpine)
	apk add --no-cache openjdk25 build-base linux-headers zip unzip curl python3 patch findutils coreutils grep sed which git bash
	echo "JAVA_HOME=/usr/lib/jvm/java-25-openjdk" >> "$GITHUB_ENV" ;;
debian|ubuntu)
	apt-get update -q; DEBIAN_FRONTEND=noninteractive apt-get install -y -q build-essential zip unzip curl python3 patch git ;;
fedora|rocky|almalinux)
	dnf install -y -q gcc gcc-c++ zip unzip curl python3 patch findutils which git tar gzip ;;
arch)
	pacman -Sy --noconfirm --quiet gcc zip unzip curl python patch which git ;;
opensuse-leap|opensuse-tumbleweed)
	zypper --non-interactive --quiet install gcc gcc-c++ zip unzip curl python3 patch findutils which git tar gzip ;;
void)
	xbps-install -Syu xbps >/dev/null; xbps-install -Sy gcc zip unzip curl python3 patch git which findutils bash tar
	# musl の Void。JDK は distro の物。25 が在れば 25、無ければ 21 で JAVA_VERSION=21
	if xbps-install -Sy openjdk25 2>/dev/null; then echo "JAVA_HOME=/usr/lib/jvm/openjdk25" >> "$GITHUB_ENV"
	else xbps-install -Sy openjdk21; echo "JAVA_HOME=/usr/lib/jvm/openjdk21" >> "$GITHUB_ENV"; echo "JAVA_VERSION=21" >> "$GITHUB_ENV"; fi ;;
chimera)
	# musl と BSD userland。toolchain は clang
	apk add --no-cache clang lld zip unzip curl python patch git bash gmake linux-headers
	if apk add --no-cache openjdk25 2>/dev/null; then echo "JAVA_HOME=$(ls -d /usr/lib/jvm/*25* | head -1)" >> "$GITHUB_ENV"
	else apk add --no-cache openjdk21; echo "JAVA_HOME=$(ls -d /usr/lib/jvm/*21* | head -1)" >> "$GITHUB_ENV"; echo "JAVA_VERSION=21" >> "$GITHUB_ENV"; fi ;;
gentoo)
	# stage3 は gcc と python を持つ。zip / unzip / git を emerge (webrsync で木を取る)
	emerge-webrsync -q; emerge -q app-arch/zip app-arch/unzip dev-vcs/git ;;
*) echo "この distro の入れ方を持っていない: $ID"; exit 1 ;;
esac
echo "### done"
