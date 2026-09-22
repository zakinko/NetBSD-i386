#!/bin/sh
# bazel master が未対応の BSD で、何が要るかを箱に訊く。数分で終わる。
#   uname、compiler の定義済み macro、JDK の版と include の dir 名、java の os.name
set -u
W=${TMPDIR:-/var/tmp}/probe.$$; mkdir -p "$W"
echo "### uname: $(uname -srm)"
echo "### /bin/sh: $(ls -l /bin/sh | sed 's/.* //')"
echo "### cc の OS macro:"; printf '' | cc -dM -E - 2>/dev/null | grep -i 'bsd\|__linux\|midnight\|dragon\|version' | head -12
echo "### JDK の候補:"
for d in /usr/pkg/java/openjdk* /usr/local/openjdk* /usr/local/jdk-* /usr/pkg/java/*; do
	[ -x "$d/bin/javac" ] || continue
	printf '  %s  ' "$d"; "$d/bin/javac" -version 2>&1 | head -1
	echo "    include: $(ls "$d/include" 2>/dev/null | grep -v '\.h$' | tr '\n' ' ')"
	cat > "$W/OsName.java" <<'J'
public class OsName { public static void main(String[] a) { System.out.println(System.getProperty("os.name") + " / " + System.getProperty("os.arch")); } }
J
	( cd "$W" && "$d/bin/javac" OsName.java 2>/dev/null && printf '    os.name: ' && "$d/bin/java" OsName ) || echo '    (java が動かない)'
done
echo "### package の JDK 25 は在るか:"
case "$(uname -s)" in
NetBSD) pkgin avail 2>/dev/null | grep -i '^openjdk' | head; pkgin avail 2>/dev/null | grep -i 'openjdk-bin' ;;
DragonFly) pkg search -q openjdk 2>/dev/null | head ;;
MidnightBSD) mport search openjdk 2>/dev/null | head ;;
esac
echo "### go / python:"; command -v go python3 python3.13 2>/dev/null; go version 2>/dev/null || true
rm -rf "$W"
