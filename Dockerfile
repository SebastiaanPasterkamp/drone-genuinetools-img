# We don't use the Alpine shadow pkg bacause:
# 1. Alpine shadow makes SUID `su` executable without password: https://github.com/gliderlabs/docker-alpine/issues/430
#    (but note that the SUID binary is not executable after unsharing the usernamespace. so this issue is not critical)
# 2. To allow running img in a container without CAP_SYS_ADMIN, we need to do either
#     a) install newuidmap/newgidmap with file capabilities rather than SETUID (requires kernel >= 4.14)
#     b) install newuidmap/newgidmap >= 20181125 (59c2dabb264ef7b3137f5edb52c0b31d5af0cf76)
#    We choose b) until kernel >= 4.14 gets widely adopted.
#    See https://github.com/shadow-maint/shadow/pull/132 https://github.com/shadow-maint/shadow/pull/138 https://github.com/shadow-maint/shadow/pull/141
FROM alpine:3.11 AS idmap

RUN apk add --no-cache \
	autoconf \
	automake \
	build-base \
	byacc \
	gettext \
	gettext-dev \
	gcc \
	git \
	libcap-dev \
	libtool \
	libxslt

WORKDIR /shadow

COPY shadow .

RUN ./autogen.sh \
		--disable-nls \
		--disable-man \
		--without-audit \
		--without-selinux \
		--without-acl \
		--without-attr \
		--without-tcb \
		--without-nscd \
	&& make \
	&& cp src/newuidmap src/newgidmap /usr/bin

FROM golang:1.13-alpine AS img

RUN apk add --no-cache \
	bash \
	build-base \
	gcc \
	git \
	libseccomp-dev \
	linux-headers \
	make

WORKDIR /img

COPY img/go.mod img/go.sum \
	/img/

RUN go get github.com/go-bindata/go-bindata/go-bindata \
	&& go mod download \
	&& go mod verify

COPY runc/go.mod runc/go.sum \
	/img/cross/src/github.com/opencontainers/runc/

RUN cd /img/cross/src/github.com/opencontainers/runc/ \
	&& go mod download \
	&& go mod verify

COPY img /img
COPY runc /img/cross/src/github.com/opencontainers/runc

RUN rm /img/cross/src/github.com/opencontainers/runc/.git || true

COPY .git/modules/img \
	/img/.git
COPY .git/modules/runc \
	/img/cross/src/github.com/opencontainers/runc/.git

RUN sed \
		-ri 's/worktree\b.*/worktree = ./g' \
		/img/cross/src/github.com/opencontainers/runc/.git/config \
	&& make static

FROM alpine:3.11 AS base

MAINTAINER Sebastiaan Pasterkamp <26205277+SebastiaanPasterkamp@users.noreply.github.com>

RUN apk add --no-cache \
	git \
	pigz

COPY --from=img /img/img /usr/bin/img
COPY --from=idmap /usr/bin/newuidmap /usr/bin/newuidmap
COPY --from=idmap /usr/bin/newgidmap /usr/bin/newgidmap
COPY plugin.sh /drone/

RUN chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap \
	&& adduser -D -u 1000 user \
	&& mkdir -p /run/user/1000 \
	&& mkdir -p /etc/docker \
	&& chown -R user /run/user/1000 /home/user /etc/docker \
	&& echo user:100000:65536 | tee /etc/subuid | tee /etc/subgid

FROM base AS debug

RUN apk add --no-cache \
	bash \
	strace

FROM base AS release

USER user

ENV USER user
ENV HOME /home/user
ENV XDG_RUNTIME_DIR=/run/user/1000

ENTRYPOINT [ "/bin/sh" ]

CMD [ "/drone/plugin.sh" ]
