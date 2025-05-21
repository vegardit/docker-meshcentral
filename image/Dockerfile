#syntax=docker/dockerfile:1
# see https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/reference.md
# see https://docs.docker.com/engine/reference/builder/#syntax
#
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com)
# SPDX-FileContributor: Sebastian Thomschke
# SPDX-License-Identifier: Apache-2.0
# SPDX-ArtifactOfProjectHomePage: https://github.com/vegardit/docker-meshcentral
#
# https://hub.docker.com/_/node/tags?name=lts-slim

ARG BASE_IMAGE=node:lts-slim

# https://github.com/hadolint/hadolint/wiki/DL3006 Always tag the version of an image explicitly
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

LABEL maintainer="Vegard IT GmbH (vegardit.com)"

# https://github.com/hadolint/hadolint/wiki/DL3002 Last USER should not be root
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG LC_ALL=C

ARG INSTALL_SUPPORT_TOOLS=0

ARG BASE_LAYER_CACHE_KEY

COPY --from=vegardit/osslsigncode:develop-debian /usr/local/bin/osslsigncode /usr/local/bin/osslsigncode
COPY --from=vegardit/softhsm2-pkcs11-proxy:develop-debian /usr/local/lib/libpkcs11-proxy* /usr/local/lib/

# https://github.com/hadolint/hadolint/wiki/DL3008 Pin versions in apt-get
# hadolint ignore=DL3008
RUN --mount=type=bind,source=.shared,target=/mnt/shared <<EOF

  /mnt/shared/cmd/debian-install-os-updates.sh
  /mnt/shared/cmd/debian-install-support-tools.sh

  echo "#################################################"
  echo "Installing tini..."
  echo "#################################################"
  apt-get install --no-install-recommends -y tini

  echo "#################################################"
  echo "Installing libraries required by osslsigncode ..."
  echo "#################################################"
  apt-get install --no-install-recommends -y \
    ca-certificates \
    libssl3 \
    libcurl4 \
    netbase

  osslsigncode --version

  echo "#################################################"
  echo "Installing libraries required by libpkcs11-proxy..."
  echo "#################################################"
  apt-get install --no-install-recommends -y libengine-pkcs11-openssl
  # -> /usr/lib/x86_64-linux-gnu/engines-1.1/pkcs11.so
  # -> /usr/lib/x86_64-linux-gnu/engines-1.1/libpkcs11.so
  # -> After this operation, 6714 kB of additional disk space will be used.
  #
  #apt-get install --no-install-recommends -y opensc-pkcs11
  # -> /usr/lib/x86_64-linux-gnu/pkcs11/opensc-pkcs11.so
  # -> /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
  # -> After this operation, 10.6 MB of additional disk space will be used.
  # -> opensc-pkcs11.so compatible with osslsigncode, results in:
  #   Failed to set 'dynamic' engine
  #   error:2506406A:DSO support routines:dlfcn_bind_func:could not bind to the requested symbol name:
  #     ../crypto/dso/dso_dlfcn.c:188:symname(bind_engine):
  #     /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so: undefined symbol: bind_engine
  #   error:2506C06A:DSO support routines:DSO_bind_func:could not bind to the requested symbol name:
  #     ../crypto/dso/dso_lib.c:186:
  #   error:260B6068:engine routines:dynamic_load:DSO failure:
  #     ../crypto/engine/eng_dyn.c:427: Failed
  #
  echo "#################################################"
  echo "Configuring Node.js ..."
  echo "#################################################"
  $(which node) -v
  $(which npm) -v
  # allow unpriviledged node process bind to priviledged ports below 1024
  apt-get install --no-install-recommends -y libcap2-bin
  setcap cap_net_bind_service=+ep "$(which node)"

  /mnt/shared/cmd/debian-cleanup.sh

EOF

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


RUN <<EOF

  echo "#################################################"
  echo "Writing build_info..."
  echo "#################################################"
  echo "
GIT_REPO:    $GIT_REPO_URL
GIT_BRANCH:  $GIT_BRANCH
GIT_COMMIT:  $GIT_COMMIT_HASH @ $GIT_COMMIT_DATE
IMAGE_BUILD: $BUILD_DATE" >/opt/build_info
  cat /opt/build_info

  echo "#################################################"
  echo "Installing meshcentral..."
  echo "#################################################"
  mkdir /opt/meshcentral
  chown -R node:node /opt/meshcentral

  # TODO temporary workaround for CVE-2024-21538, see https://github.com/npm/cli/issues/7902
  rm -rf /usr/local/lib/node_modules/npm/node_modules/cross-spawn

EOF

USER node

WORKDIR /opt/meshcentral

# see https://github.com/hadolint/hadolint/wiki/DL3016 Pin versions in npm
# hadolint ignore=DL3016
RUN <<EOF

  set -x
  echo '{
    "name": "meshcentral-server",
    "version": "0.0.0"
}' > package.json

  npm install meshcentral --omit=dev
  npm list
  node ./node_modules/meshcentral --help
EOF

COPY image/run.sh /opt/run.sh
COPY .shared/lib/bash-init.sh /opt/bash-init.sh

VOLUME ["/opt/meshcentral/meshcentral-data", "/opt/meshcentral/meshcentral-files"]

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/bin/bash", "/opt/run.sh"]
