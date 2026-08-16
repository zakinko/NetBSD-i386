
# $FML: Makefile,v 1.118 2026/08/09 08:52:03 fukachan Exp $
#

_host		!= hostname -s
_fqdn		!= hostname
_is_diskless	!= ls /.__diskless__ >/dev/null 2>&1 && echo less || echo full
opt_install	 =
opt_build	 = -package
opt_fetch	 = -fetch
opt_force	 = -force
opt_package	 = -package -force
PROG_ENV         = /usr/bin/env -i
PROG_BOOTSTRAP   = ${PROG_ENV} ./pkgsrc-bootstrap.sh
WORK_PKGSRC      = /var/tmp/pkgsrc.work
DATE_SFX         != date +%s

# roles vs packages
pkg.all		 = base sh client doc mail tex www comms
pkg.base         = base
pkg.client	 = base         client

# roles
elena.role	= ${pkg.base}    mail
beth.role	= ${pkg.base}    mail
viper.role	= ${pkg.base}
eidos.role	= ${pkg.base} sh
logos.role	= ${pkg.base} sh
idea.role	= ${pkg.base} sh
eikon.role	= ${pkg.base} sh
techne.role	= ${pkg.base} sh

# viper* must be a clicent same as katri.
.if !empty(_host:Mviper*)
${_host}.role = ${viper.role}
.endif

# nofs* must be a file server.
.if !empty(_fqdn:M*.snowrabbit.org)
${_host}.role = ${pkg.base} sh ns www aws
.endif

# by default
.if empty(${_host}.role)
${_host}.role += base
.endif

# LAST: local hack.
.if exists(list.pkg.local)
${_host}.role += local
.endif

all:
	@ echo "make clean"
	@ echo "make audit"
	@ echo ""
	@ echo "1. for ordinary use"
	@ echo "make install		(bin-install if could, or install)"
	@ echo "make install-all	(bin-install if could, or install)"
	@ echo ""
	@ echo "2. to rebuild packages."
	@ echo "make package		(package and bin-install)"
	@ echo "make package-all	(package and bin-install)"

install:
	${PROG_BOOTSTRAP} ${opt_install} ${${_host}.role}

install-all:
	${PROG_BOOTSTRAP} ${opt_install} ${pkg.all}

build:
	${PROG_BOOTSTRAP} ${opt_build} ${${_host}.role}

build-force:
	${PROG_BOOTSTRAP} ${opt_build} ${${_host}.role}

package:
	${PROG_BOOTSTRAP} ${opt_package} ${${_host}.role}
	sh pkgsrc-build-pkg-summary.sh

package-all:
	${PROG_BOOTSTRAP} ${opt_package} ${pkg.all}
	sh pkgsrc-build-pkg-summary.sh

pkg-summary:
	@ sh pkgsrc-build-pkg-summary.sh

summary: pkg-summary

# /usr/pkgsrc is git on some boxes and cvs on others, so look before pulling.
# "[ -d ... ] && cmd" cannot do this: on a cvs box the test is false, the line
# exits 1, and make stops before pkg_rolling-replace ever runs.
#
# cvs update over the whole of pkgsrc talks to the server once per directory
# and takes long enough that running it on every "make update" is the reason
# not to run "make update".  So it is skipped when it ran recently.  git needs
# no such guard -- one fetch is one round trip -- and is left alone.
#
# The stamp is separate because cvs, unlike git, leaves no trace of an update
# that found nothing: CVS/Entries is only rewritten where something changed.
# A missing or unwritable stamp means "do it", which is the safe direction.
#
# CVS_MAXAGE is in minutes.  "make update CVS_MAXAGE=0" always updates.
CVS_MAXAGE	 = 720
CVS_STAMP	 = /var/db/pkgsrc-cvs-update.stamp

update:
	@ if [ -d /usr/pkgsrc/.git ]; then \
		echo "==> /usr/pkgsrc: git"; \
		(cd /usr/pkgsrc; git pull --rebase); \
	elif [ -d /usr/pkgsrc/CVS ]; then \
		if [ ${CVS_MAXAGE} -gt 0 ] && \
		   [ -n "`find ${CVS_STAMP} -mmin -${CVS_MAXAGE} 2>/dev/null`" ]; then \
			echo "==> /usr/pkgsrc: cvs, updated within ${CVS_MAXAGE}min, skipped"; \
		else \
			echo "==> /usr/pkgsrc: cvs"; \
			if (cd /usr/pkgsrc; cvs -q update -dP); then \
				touch ${CVS_STAMP} 2>/dev/null || true; \
			else exit 1; fi; \
		fi; \
	else \
		echo "==> /usr/pkgsrc: neither, left alone"; \
	fi
	@ if [ -d /usr/pkgsrc/wip/.git ]; then \
		echo "==> /usr/pkgsrc/wip: git"; \
		(cd /usr/pkgsrc/wip; git pull --rebase); \
	elif [ -d /usr/pkgsrc/wip/CVS ]; then \
		if [ ${CVS_MAXAGE} -gt 0 ] && \
		   [ -n "`find ${CVS_STAMP}.wip -mmin -${CVS_MAXAGE} 2>/dev/null`" ]; then \
			echo "==> /usr/pkgsrc/wip: cvs, updated within ${CVS_MAXAGE}min, skipped"; \
		else \
			echo "==> /usr/pkgsrc/wip: cvs"; \
			if (cd /usr/pkgsrc/wip; cvs -q update -dP); then \
				touch ${CVS_STAMP}.wip 2>/dev/null || true; \
			else exit 1; fi; \
		fi; \
	fi
	/usr/pkg/sbin/pkg_rolling-replace -Fv
	/usr/pkg/sbin/pkg_rolling-replace -suv
	@ make update-check-template-show
	sh pkgsrc-build-pkg-summary.sh

update-check-template-show:
	@ echo ""; 
	@ echo "apply 'echo %1 restart' /usr/pkg/share/examples/rc.d/*|grep -v /sshd|sh"
	@ echo "ps auxww |egrep '/sbin'"
	@ echo ""
	@ sh pkgsrc-check-daemon.sh
	@ echo ""

fetch:
	${PROG_BOOTSTRAP} ${opt_fetch} ${${_host}.role}

fetch-all:
	${PROG_BOOTSTRAP} ${opt_fetch} ${pkg.all}

clean:
	rm -f *~
	@ [ -d ${WORK_PKGSRC} ] && mv -v ${WORK_PKGSRC} ${WORK_PKGSRC}.${DATE_SFX} || true

audit:
	@ sh pkgsrc-audit.sh
