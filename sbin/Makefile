
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

update:
	[ -d /usr/pkgsrc/.git     ] && (cd /usr/pkgsrc/;    git pull --rebase)
	[ -d /usr/pkgsrc/wip/.git ] && (cd /usr/pkgsrc/wip; git pull --rebase)
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
