#!/bin/sh
# Linux の container に、bazel の bootstrap に要る道具を入れる。distro は
# /etc/os-release で見分ける。musl の箱では temurin (glibc 向け) が動かないので
# distro の JDK を入れ、JAVA_HOME と (25 が無ければ) JAVA_VERSION を GITHUB_ENV へ書く。
# glibc の箱は JDK を入れず、あとの setup-java (temurin 25) に任せる。
set -eu
. /etc/os-release
echo "### distro: $ID ${VERSION_ID:-}  /bin/sh -> $(readlink -f /bin/sh)  musl: $(ls /lib/ld-musl-* 2>/dev/null || echo no)"
case "$ID" in
alpine)
	apk add --no-cache openjdk25 build-base linux-headers zip unzip curl python3 patch findutils coreutils grep sed which git bash
	echo "JAVA_HOME=/usr/lib/jvm/java-25-openjdk" >> "$GITHUB_ENV" ;;
debian|ubuntu)
	apt-get update -q; DEBIAN_FRONTEND=noninteractive apt-get install -y -q build-essential zip unzip curl python3 patch git ;;
fedora|rocky|almalinux)
	# Rocky 9 の像は curl-minimal を持ち、curl と衝突する (run 35676218786)。
	# --allowerasing で入れ替えさせる
	dnf install -y -q --allowerasing gcc gcc-c++ zip unzip curl python3 patch findutils which git tar gzip
	# docker run の箱 (IN_DOCKER) には setup-java が届かないので distro の JDK を
	# 入れる。container: の箱 (fedora) はあとの setup-java に任せる
	if [ -n "${IN_DOCKER:-}" ] && dnf install -y -q java-25-openjdk-devel 2>/dev/null; then
		echo "JAVA_HOME=$(ls -d /usr/lib/jvm/java-25-openjdk* | head -1)" >> "$GITHUB_ENV"
	elif [ -n "${IN_DOCKER:-}" ] && dnf install -y -q java-21-openjdk-devel 2>/dev/null; then
		echo "JAVA_HOME=$(ls -d /usr/lib/jvm/java-21-openjdk* | head -1)" >> "$GITHUB_ENV"; echo "JAVA_VERSION=21" >> "$GITHUB_ENV"
	fi ;;
arch)
	pacman -Sy --noconfirm --quiet gcc zip unzip curl python patch which git ;;
opensuse-leap|opensuse-tumbleweed)
	zypper --non-interactive --quiet install gcc gcc-c++ zip unzip curl python3 patch findutils which git tar gzip
	# docker run で回すので setup-java が無い。distro の JDK を入れる。25 が
	# 無ければ 21 で JAVA_VERSION=21
	if zypper --non-interactive --quiet install java-25-openjdk-devel 2>/dev/null; then
		echo "JAVA_HOME=$(ls -d /usr/lib64/jvm/java-25-openjdk* | head -1)" >> "$GITHUB_ENV"
	else
		zypper --non-interactive --quiet install java-21-openjdk-devel
		echo "JAVA_HOME=$(ls -d /usr/lib64/jvm/java-21-openjdk* | head -1)" >> "$GITHUB_ENV"; echo "JAVA_VERSION=21" >> "$GITHUB_ENV"
	fi ;;
void)
	# 既定の mirror (alpha.de) は証明書の名前が合わず、xbps が
	# "Operation not permitted" で止まる (run 35703229138)。repo を
	# repo-default.voidlinux.org に向け直す。
	mkdir -p /etc/xbps.d
	printf 'repository=https://repo-default.voidlinux.org/current/musl\n' > /etc/xbps.d/00-repository-main.conf
	xbps-install -Syu xbps >/dev/null; xbps-install -Sy gcc zip unzip curl python3 patch git which findutils bash tar
	# musl の Void。JDK は distro の物。25 が在れば 25、無ければ 21 で JAVA_VERSION=21
	if xbps-install -Sy openjdk25 2>/dev/null; then echo "JAVA_HOME=/usr/lib/jvm/openjdk25" >> "$GITHUB_ENV"
	else xbps-install -Sy openjdk21; echo "JAVA_HOME=/usr/lib/jvm/openjdk21" >> "$GITHUB_ENV"; echo "JAVA_VERSION=21" >> "$GITHUB_ENV"; fi ;;
chimera)
	# musl と BSD userland。toolchain は clang
	# Chimera に patch という package は無い (run 35703229138)。base-devel が
	# 持っている。python は python3 の名前でなく python
	apk add --no-cache clang lld zip unzip curl python base-devel git bash linux-headers
	# patch(1) は chimerautils-extra に在る (cports の main/chimerautils の
	# template.py が cmd:patch をそこへ入れている)。patch という package は無い
	apk add --no-cache chimerautils-extra
	command -v patch >/dev/null || { echo "chimera に patch が無い"; exit 1; }
	if apk add --no-cache openjdk25 2>/dev/null; then echo "JAVA_HOME=$(ls -d /usr/lib/jvm/*25* | head -1)" >> "$GITHUB_ENV"
	else apk add --no-cache openjdk21; echo "JAVA_HOME=$(ls -d /usr/lib/jvm/*21* | head -1)" >> "$GITHUB_ENV"; echo "JAVA_VERSION=21" >> "$GITHUB_ENV"; fi ;;
gentoo)
	# stage3 は gcc と python を持つ。zip / unzip / git を emerge (webrsync で木を取る)
	emerge-webrsync -q; emerge -q app-arch/zip app-arch/unzip dev-vcs/git ;;
*) echo "この distro の入れ方を持っていない: $ID"; exit 1 ;;
esac
# Rocky の像は Config.Env に PATH を持たず、setup-java が GITHUB_PATH に足すと
# runner が組み立てる次の step の PATH が JDK の bin だけになり、sh すら
# 見つからなくなる (run 35692632379: exec: "sh": executable file not found)。
# 今の PATH を GITHUB_ENV に書いておくと、runner はそれに足す形になる。
echo "PATH=$PATH" >> "$GITHUB_ENV"
echo "### done"
