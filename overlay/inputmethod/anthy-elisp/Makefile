# $NetBSD: Makefile,v 1.14 2024/05/08 12:20:52 wiz Exp $
#
# 上流 pkgsrc の inputmethod/anthy-elisp/Makefile の写しに、
# EMACS_VERSIONS_ACCEPTED を広げただけのもの。
#
# 上流は emacs21 世代と XEmacs しか受け付けない。この行は 2013 年から
# そのままで、Makefile 自体は 2024 年に触られているので、単に誰も
# 新しい Emacs で試していないだけに見える。そのため
#
#	editors/emacs/modules.mk
#	.if empty(EMACS_VERSIONS_ACCEPTED:M${_EMACS_TYPE})
#	PKG_FAIL_REASON+= "No valid Emacs version installed found"
#
# で、emacs26nox でも建たない。anthy.el を入れるのはこのパッケージだけ
# (あとは tamago 系) なので、~/.emacs の (load-library "anthy") が
# 効かなくなる。
#
# ここでは 26 以降を足して、実際に byte-compile が通るかを見る。通れば
# 上流 (MAINTAINER: taya@NetBSD.org) に送る。通らなければ入力方式を
# inputmethod/ddskk か mozc-elisp に移すことになる。
#
# PKGREVISION は上げていない。中身は変わらず、受け付ける版が増えるだけで、
# 建つ Emacs が変われば PKGNAME の側 (EMACS_PKGNAME_PREFIX) が変わる。

.include	"../../inputmethod/anthy/Makefile.common"
PKGNAME=	${EMACS_PKGNAME_PREFIX}anthy-elisp-${ANTHY_VERSION}
PKGREVISION=	6
CATEGORIES=	inputmethod editors

MAINTAINER=	taya@NetBSD.org
COMMENT=	Emacs lisp files for inputmethod/anthy

DEPENDS+=	anthy>=${ANTHY_VERSION}:../../inputmethod/anthy

GNU_CONFIGURE=	yes
CONFIGURE_ENV+=	EMACS=${EMACS_BIN:Q}
EMACS_MODULES+=	base leim

EMACS_VERSIONS_ACCEPTED=	emacs21 emacs21nox emacs20
EMACS_VERSIONS_ACCEPTED+=	xemacs215 xemacs215nox xemacs214 xemacs214nox
EMACS_VERSIONS_ACCEPTED+=	emacs26 emacs26nox
EMACS_VERSIONS_ACCEPTED+=	emacs27 emacs27nox
EMACS_VERSIONS_ACCEPTED+=	emacs28 emacs28nox
EMACS_VERSIONS_ACCEPTED+=	emacs29 emacs29nox
EMACS_VERSIONS_ACCEPTED+=	emacs30 emacs30nox

.include "../../editors/emacs/modules.mk"

do-build:
	cd ${WRKSRC}/src-util && ${MAKE} elc-stamp

do-install:
	${INSTALL_DATA_DIR} ${DESTDIR}${EMACS_LISPPREFIX}/anthy
	${INSTALL_DATA} ${WRKSRC}/src-util/*.el	 ${DESTDIR}${EMACS_LISPPREFIX}/anthy
	${INSTALL_DATA} ${WRKSRC}/src-util/*.elc ${DESTDIR}${EMACS_LISPPREFIX}/anthy

.include "../../mk/bsd.pkg.mk"
