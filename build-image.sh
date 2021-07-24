#!/usr/bin/env bash
#
# Copyright 2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# Author: Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/docker-meshcentral
#

shared_lib="$(dirname $0)/.shared"
[ -e "$shared_lib" ] || curl -sSf https://raw.githubusercontent.com/vegardit/docker-shared/v1/download.sh?_=$(date +%s) | bash -s v1 "$shared_lib" || exit 1
source "$shared_lib/lib/build-image-init.sh"


#################################################
# specify target docker registry/repo
#################################################
docker_registry=${DOCKER_REGISTRY:-docker.io}
image_repo=${DOCKER_IMAGE_REPO:-vegardit/meshcentral}
image_name=$image_repo:${DOCKER_IMAGE_TAG:-latest}


#################################################
# build the image
#################################################
echo "Building docker image [$image_name]..."
if [[ $OSTYPE == "cygwin" || $OSTYPE == "msys" ]]; then
   project_root=$(cygpath -w "$project_root")
fi

DOCKER_BUILDKIT=1 docker build "$project_root" \
   --file "image/Dockerfile" \
   --progress=plain \
   --pull \
   --build-arg INSTALL_SUPPORT_TOOLS=${INSTALL_SUPPORT_TOOLS:-0} \
   `# using the current date as value for BASE_LAYER_CACHE_KEY, i.e. the base layer cache (that holds system packages with security updates) will be invalidate once per day` \
   --build-arg BASE_LAYER_CACHE_KEY=$base_layer_cache_key \
   --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
   --build-arg GIT_BRANCH="${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}" \
   --build-arg GIT_COMMIT_DATE="$(date -d @$(git log -1 --format='%at') --utc +'%Y-%m-%d %H:%M:%S UTC')" \
   --build-arg GIT_COMMIT_HASH="$(git rev-parse --short HEAD)" \
   --build-arg GIT_REPO_URL="$(git config --get remote.origin.url)" \
   -t $image_name \
   "$@"


#################################################
# determine effective version and apply tags
#################################################
# LC_ALL=en_US.utf8 -> workaround for "grep: -P supports only unibyte and UTF-8 locales"
# 2>/dev/null -> workaround for "write /dev/stdout: The pipe is being closed."
meshcentral_version=$(docker run --rm $image_name node node_modules/meshcentral --help 2>/dev/null | head -1 | LC_ALL=en_US.utf8 grep -oP 'MeshCentral v\K\d+\.\d+\.\d+' || true)
echo "meshcentral_version=$meshcentral_version"
docker image tag $image_name $image_repo:${meshcentral_version%.*}.x  #2.4.x
docker image tag $image_name $image_repo:${meshcentral_version%%.*}.x #2.x


#################################################
# perform security audit
#################################################
bash "$shared_lib/cmd/audit-image.sh" $image_name


#################################################
# push image with tags to remote docker image registry
#################################################
if [[ "${DOCKER_PUSH:-0}" == "1" ]]; then
   docker image tag $image_name $docker_registry/$image_name
   #docker image tag $image_name $docker_registry/$image_repo:${meshcentral_version}       #0.88.3
   docker image tag $image_name $docker_registry/$image_repo:${meshcentral_version%.*}.x  #0.88.x
   docker image tag $image_name $docker_registry/$image_repo:${meshcentral_version%%.*}.x #0.x

   docker push $docker_registry/$image_name
   #docker push $docker_registry/$image_repo:${meshcentral_version}       #0.88.3
   docker push $docker_registry/$image_repo:${meshcentral_version%.*}.x  #0.88.x
   docker push $docker_registry/$image_repo:${meshcentral_version%%.*}.x #0.x
fi
