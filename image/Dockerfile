#syntax=docker/dockerfile:1
# Copyright 2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# Author: Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/docker-meshcentral
#

FROM node:lts-buster-slim

LABEL maintainer="Vegard IT GmbH (vegardit.com)"

USER root

SHELL ["/bin/bash", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG LC_ALL=C

ARG BASE_LAYER_CACHE_KEY
ARG INSTALL_SUPPORT_TOOLS=0

COPY --from=vegardit/osslsigncode:develop-debian /usr/local/bin/osslsigncode /usr/local/bin/osslsigncode

RUN --mount=type=bind,source=.shared,target=/mnt/shared \
  set -eu && \
  /mnt/shared/cmd/debian-install-os-updates.sh && \
  /mnt/shared/cmd/debian-install-support-tools.sh && \
  #
  echo "#################################################" && \
  echo "Installing tini..." && \
  echo "#################################################" && \
  apt-get install --no-install-recommends -y tini && \
  #
  echo "#################################################" && \
  echo "Installing libraries required by osslsigncode ..." && \
  echo "#################################################" && \
  apt-get install --no-install-recommends -y \
     ca-certificates \
     libssl1.1 \
     libcurl4 \
     netbase \
     && \
  osslsigncode --version && \
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
  /mnt/shared/cmd/debian-cleanup.sh

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
  INIT_SH_FILE='' \
  #
  CONFIG_TEMPLATE_FILE='' \
  OSSLSIGNCODE_OPTS=''


RUN \
  set -eu && \
  echo -e "\
GIT_REPO:    $GIT_REPO_URL\n\
GIT_BRANCH:  $GIT_BRANCH\n\
GIT_COMMIT:  $GIT_COMMIT_HASH @ $GIT_COMMIT_DATE\n\
IMAGE_BUILD: $BUILD_DATE\n" >/opt/build_info && \
  cat /opt/build_info && \
  #
  echo "#################################################" && \
  echo "Installing meshcentral..." && \
  echo "#################################################" && \
  mkdir /opt/meshcentral && \
  chown -R node:node /opt/meshcentral

USER node

WORKDIR /opt/meshcentral

RUN \
  set -eu && \
  echo -e '{\n\
    "name": "meshcentral-server",\n\
    "version": "0.0.0"\n\
}' > package.json && \
  npm install meshcentral --only=production && \
  node ./node_modules/meshcentral --help

COPY image/run.sh /opt/run.sh
COPY .shared/lib/bash-init.sh /opt/bash-init.sh

VOLUME ["/opt/meshcentral/meshcentral-data", "/opt/meshcentral/meshcentral-files"]

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/bin/bash", "/opt/run.sh"]
