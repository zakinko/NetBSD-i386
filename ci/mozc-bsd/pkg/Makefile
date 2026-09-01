# $NetBSD: Makefile,v 1.104 2026/05/14 16:41:20 ryoon Exp $

PKGNAME=	${DISTNAME:S/mozc-/mozc-server-/}
PKGREVISION=	14

INSTALLATION_DIRS+=	libexec

.include "../../zakinko/mozc-server/options.mk"

post-configure:
	cd ${WRKSRC}/dist && \
		unzip -d ../dictionary jigyosyo.zip && \
		unzip -d ../dictionary ken_all.zip

.if empty(PKG_OPTIONS:Mgyp)
do-build:
	cd ${WRKSRC} && ${SETENV} ${MAKE_ENV} \
		${PREFIX}/bin/bazel \
			--output_user_root=${WRKDIR}/bazel \
			--client_debug \
			build \
			server:mozc_server \
			--host_action_env=CWRAPPERS_CONFIG_DIR=${CWRAPPERS_CONFIG_DIR} \
			--action_env=CWRAPPERS_CONFIG_DIR=${CWRAPPERS_CONFIG_DIR} \
			--host_action_env=PATH=${PATH} \
			--action_env=PATH=${PATH} \
			--sandbox_debug \
			--verbose_failures \
			--subcommands \
			--distdir=${WRKSRC}/dist \
			--jobs=${MAKE_JOBS:U1} \
			${BAZEL_ARGS} \
			--config oss_linux --compilation_mode opt

do-install:
	${INSTALL_PROGRAM} ${WRKSRC}/bazel-out/${OSDEST}/bin/server/mozc_server \
		${DESTDIR}${PREFIX}/libexec/mozc_server
.else
do-build:
	cd ${WRKSRC} && ${SETENV} ${MAKE_ENV} \
		${PYTHONBIN} build_mozc.py build -c ${MOZC_BUILD_MODE} \
			server/server.gyp:mozc_server

do-install:
	${INSTALL_PROGRAM} ${WRKSRC}/out_${OSDEST}/${MOZC_BUILD_MODE}/mozc_server \
		${DESTDIR}${PREFIX}/libexec/mozc_server
.endif

.include "Makefile.common"
.include "../../mk/bsd.pkg.mk"
