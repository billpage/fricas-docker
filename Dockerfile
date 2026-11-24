# FriCAS (from git) on SBCL (from source), for STRIX.
# Build with `make build` (see Makefile for the arguments and README.md for use).
FROM ubuntu:24.04

ARG SBCL_TAG=sbcl-2.6.10
# --dynamic-space-size here sets SBCL's *default* heap; saved cores such as
# FRICASsys inherit it, so FriCAS needs no extra runtime option.
ARG SBCL_OPTS="--fancy --dynamic-space-size=8Gb"
ARG FRICAS_REF=1.4.0
ARG FRICAS_CONFIGURE="--enable-gmp"
ARG JOBS=12
# 1 = run FriCAS's `make check` once while the build tree exists; log kept in the image.
# It runs as user fricas: as root, files.input's chmod-400 test cannot fail as expected.
ARG RUN_CHECK=1
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git ca-certificates curl less rlwrap \
        sbcl zlib1g-dev libzstd-dev libgmp-dev \
        libx11-dev libxt-dev libice-dev libsm-dev libxau-dev libxdmcp-dev libxpm-dev \
        xvfb xauth \
 && rm -rf /var/lib/apt/lists/*

# --- SBCL from source; Ubuntu's sbcl is only the bootstrap host and is removed after
RUN git clone --depth 1 --branch "${SBCL_TAG}" https://github.com/sbcl/sbcl /tmp/sbcl \
 && cd /tmp/sbcl \
 && printf '"%s"\n' "${SBCL_TAG#sbcl-}" > version.lisp-expr && rm -rf .git \
 && sh make.sh --prefix=/usr/local ${SBCL_OPTS} \
 && INSTALL_ROOT=/usr/local sh install.sh \
 && cd / && rm -rf /tmp/sbcl \
 && apt-get purge -y sbcl && apt-get autoremove -y \
 && /usr/local/bin/sbcl --version

# --- user fricas = wspage's UID/GID, so files in the bind mounts belong to wspage
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g "${GID}" fricas \
 && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash fricas \
 && mkdir -p /home/fricas/work /home/fricas/dev \
 && chown -R fricas:fricas /home/fricas

# --- Release FriCAS from git, out-of-tree build; source kept in /usr/local/src/fricas
RUN git clone --depth 1 --branch "${FRICAS_REF}" https://github.com/fricas/fricas /usr/local/src/fricas \
 && mkdir /tmp/fb && cd /tmp/fb \
 && /usr/local/src/fricas/configure --prefix="/opt/fricas/${FRICAS_REF}" \
        --with-lisp=/usr/local/bin/sbcl ${FRICAS_CONFIGURE} \
 && make -j"${JOBS}" \
 && make install \
 && if [ "${RUN_CHECK}" = 1 ]; then \
        chown -R fricas:fricas /tmp/fb \
        && (runuser -u fricas -- make -j"${JOBS}" check > "/opt/fricas/${FRICAS_REF}/make-check.log" 2>&1 \
         && echo "make check: ok" || echo "make check: FAILED (see make-check.log)") \
        | tee "/opt/fricas/${FRICAS_REF}/make-check.status"; \
    fi \
 && ln -s "/opt/fricas/${FRICAS_REF}" /opt/fricas/release \
 && cd / && rm -rf /tmp/fb

COPY --chmod=755 scripts/ /usr/local/bin/

USER fricas
WORKDIR /home/fricas/work
ENV FRICAS_DEV=/home/fricas/dev
CMD ["sleep", "infinity"]
