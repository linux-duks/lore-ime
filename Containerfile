FROM docker.io/library/debian:trixie-slim as base

ARG USER_ID=1000
ARG GROUP_ID=1000

# Install shared dependencies
USER root
RUN export DEBIAN_FRONTEND=noninteractive &&\
	apt-get update && \
	apt-get install -y \
	git \
	perl \
	python3 \
	python3-pip \
	sqlite3 \
	curl \
	make \
	build-essential \
	# xapian search
	xapian-omega \
	libsearch-xapian-perl \
	# public-inbox \
	libplack-perl \
	libinline-c-perl \
	libemail-address-xs-perl \
	libplack-middleware-reverseproxy-perl \
	libhighlight-perl \
	libnet-server-perl \
	libmail-imapclient-perl \
	libnet-server-perl \
	spamd \
	spamc



# install grokmirror from source
WORKDIR /grokmirror
COPY ./grokmirror/ /grokmirror/
RUN pip install --break-system-packages .

# install public-inbox from source
WORKDIR /public-inbox

COPY ./public-inbox/ /public-inbox/

RUN yes | ./install/deps.perl all

RUN perl Makefile.PL && \
	make && \
	make install

WORKDIR /data
