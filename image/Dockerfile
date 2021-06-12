# Copyright 2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# Author: Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/docker-meshcentral
#

# syntax=docker/dockerfile:1


#############################################################
# build osslsigncode code signing tool
#############################################################
FROM  debian:buster-slim

RUN \
  set -eu && \
  apt-get update && \
  apt-get install --no-install-recommends -y \
    # required for curl:
    ca-certificates \
    curl \
    # required for bootstrap:
    autoconf \
    automake \
    libtool \
    python3-pkgconfig \
    # required for configure/make:
    build-essential \
    libssl-dev \
    libcurl4-gnutls-dev \
    && \
  echo "#################################################" && \
  echo "Building osslsigncode ..." && \
  echo "#################################################" && \
  curl -fsSL https://github.com/mtrojnar/osslsigncode/tarball/master | tar xvz && \
  mv mtrojnar-osslsigncode-* osslsigncode && \
  cd osslsigncode && \
  ./bootstrap && \
  ./configure && \
  make && \
  strip osslsigncode && \
  # https://github.com/mtrojnar/osslsigncode/issues/102
  ./osslsigncode --version


#############################################################
# build meshcentral image
#############################################################
FROM node:lts-buster-slim

LABEL maintainer="Vegard IT GmbH (vegardit.com)"

USER root

SHELL ["/bin/bash", "-c"]

# if set to 1 debug tools are added to the image (htop,less,mc,vim)
ARG DEBUG_BUILD=0

ARG DEBIAN_FRONTEND=noninteractive
ARG LC_ALL=C

RUN \
  set -eu && \
  echo "#################################################" && \
  echo "Installing OS updates..." && \
  echo "#################################################" && \
  apt-get update -y && \
  # https://github.com/phusion/baseimage-docker/issues/319
  apt-get install --no-install-recommends -y apt-utils 2> >( grep -v 'debconf: delaying package configuration, since apt-utils is not installed' >&2 ) && \
  apt-get upgrade -y && \
  #
  if [ "${DEBUG_BUILD}" = "1" ]; then \
     echo "#################################################" && \
     echo "Installing debugging tools..." && \
     echo "#################################################" && \
     apt-get install --no-install-recommends -y libcomerr2 mc && \
     apt-get install --no-install-recommends -y htop less procps vim && \
     echo -e 'set ignorecase\n\
set showmatch\n\
set novisualbell\n\
set noerrorbells\n\
syntax enable\n\
set mouse-=a' > ~/.vimrc; \
  fi && \
  #
  echo "#################################################" && \
  echo "Installing libraries required by osslsigncode ..." && \
  echo "#################################################" && \
  apt-get install --no-install-recommends -y libssl1.1 libcurl3-gnutls && \
  #
  echo "#################################################" && \
  echo "Configuring Node.js ..." && \
  echo "#################################################" && \
  $(which node) -v && \
  $(which npm) -v && \
  # allow unpriviledged node process bind to priviledged ports below 1024
  apt-get install --no-install-recommends -y libcap2-bin && \
  setcap cap_net_bind_service=+ep $(which node) && \
  #
  echo "#################################################" && \
  echo "apt-get clean up..." && \
  echo "#################################################" && \
  apt-get remove apt-utils -y && \
  apt-get clean autoclean && \
  apt-get autoremove --purge -y && \
  #
  echo "#################################################" && \
  echo "Removing logs, caches and temp files..." && \
  echo "#################################################" && \
  rm -rf /var/cache/{apt,debconf} \
     /var/lib/apt/lists/* \
     /var/log/{apt,alternatives.log,bootstrap.log,dpkg.log} \
     /tmp/* /var/tmp/*

COPY --from=0 /osslsigncode/osslsigncode /usr/local/bin/osslsigncode

ARG BUILD_DATE
ARG GIT_BRANCH
ARG GIT_COMMIT_HASH
ARG GIT_COMMIT_DATE
ARG GIT_REPO_URL

LABEL \
  org.label-schema.schema-version="1.0" \
  org.label-schema.build-date=$BUILD_DATE \
  org.label-schema.vcs-ref=$GIT_COMMIT_HASH \
  org.label-schema.vcs-url=$GIT_REPO_URL

# Default configuration: can be overridden at the docker command line
ENV \
  DEBUG_RUN_SH=0  \
  INIT_SH_FILE='' \
  CONFIG_TEMPLATE_FILE='' \
  OSSLSIGNCODE_OPTS=''

COPY run.sh /opt/run.sh

RUN \
  echo "GIT_REPO:    $GIT_REPO_URL" > /opt/build_info && \
  echo "GIT_BRANCH:  $GIT_BRANCH" >> /opt/build_info && \
  echo "GIT_COMMIT:  $GIT_COMMIT_HASH @ $GIT_COMMIT_DATE" >> /opt/build_info  && \
  echo "IMAGE_BUILD: $BUILD_DATE" >> /opt/build_info && \
  cat /opt/build_info && \
  echo "#################################################" && \
  echo "Installing meshcentral..." && \
  echo "#################################################" && \
  mkdir /opt/meshcentral && \
  chown -R node:node /opt/meshcentral

USER node

WORKDIR /opt/meshcentral

RUN \
  echo -e '{\n\
    "name": "meshcentral-server",\n\
    "version": "0.0.0"\n\
}' > package.json && \
  npm install meshcentral --only=production && \
  node ./node_modules/meshcentral --help

VOLUME ["/opt/meshcentral/meshcentral-data", "/opt/meshcentral/meshcentral-files"]

ENTRYPOINT ["/bin/sh", "-c"]

# exec is required for propagating SIGTERM from docker to child process
CMD ["exec /bin/bash /opt/run.sh"]
