#!/usr/bin/env bash
#
# Copyright 2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# Author: Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/docker-meshcentral
#

set -eu

#################################################
# execute script with bash if loaded with other shell interpreter
#################################################
if [ -z "${BASH_VERSINFO:-}" ]; then /usr/bin/env bash "$0" "$@"; exit; fi

set -o pipefail

trap 'echo >&2 "$(date +%H:%M:%S) Error - exited with status $? at line $LINENO:"; pr -tn $0 | tail -n+$((LINENO - 3)) | head -n7' ERR


#################################################
# specify target docker registry/repo
#################################################
docker_registry=${DOCKER_REGISTRY:-docker.io}
image_repo=${DOCKER_IMAGE_REPO:-vegardit/meshcentral}
image_name=$image_repo:${DOCKER_IMAGE_TAG:-latest}


#################################################
# determine directory of current script
#################################################
project_root=$(readlink -e $(dirname "${BASH_SOURCE[0]}"))


#################################################
# ensure Linux new line chars
#################################################
# env -i PATH="$PATH" -> workaround for "find: The environment is too large for exec()"
env -i PATH="$PATH" find "$project_root/image" -type f -exec dos2unix {} \;



#################################################
# build the image
#################################################
echo "Building docker image [$image_name]..."
if [[ $OSTYPE == "cygwin" || $OSTYPE == "msys" ]]; then
   project_root=$(cygpath -w "$project_root")
fi

docker build "$project_root/image" \
   --progress=plain \
   --pull \
   --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
   --build-arg GIT_BRANCH="${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}" \
   --build-arg GIT_COMMIT_DATE="$(date -d @$(git log -1 --format='%at') --utc +'%Y-%m-%d %H:%M:%S UTC')" \
   --build-arg GIT_COMMIT_HASH="$(git rev-parse --short HEAD)" \
   --build-arg GIT_REPO_URL="$(git config --get remote.origin.url)" \
   -t $image_name \
   "$@"


#################################################
# perform security audit using https://github.com/aquasecurity/trivy
#################################################
if [[ $OSTYPE != cygwin ]] && [[ $OSTYPE != msys ]]; then
   trivy_cache_dir="${TRIVY_CACHE_DIR:-$HOME/.trivy/cache}"
   trivy_cache_dir="${trivy_cache_dir/#\~/$HOME}"
   mkdir -p "$trivy_cache_dir"
   docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      -v "$trivy_cache_dir:/root/.cache/" \
      aquasec/trivy --no-progress \
        --severity HIGH,CRITICAL \
        --exit-code 0 \
        $image_name
   docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      -v "$project_root/.trivyignore":/.trivyignore \
      -v "$trivy_cache_dir:/root/.cache/" \
      aquasec/trivy --no-progress \
        --severity HIGH,CRITICAL \
        --ignore-unfixed \
        --ignorefile /.trivyignore \
        --exit-code 1 \
        $image_name

   sudo chown -R $USER:$(id -gn) "$trivy_cache_dir" || true
fi

#################################################
# determine effective version and apply tags
#################################################
# LC_ALL=en_US.utf8 -> workaround for "grep: -P supports only unibyte and UTF-8 locales"
# 2>/dev/null -> workaround for "write /dev/stdout: The pipe is being closed."
meshcentral_version=$(docker run --rm $image_name "node node_modules/meshcentral --help" 2>/dev/null | head -1 | LC_ALL=en_US.utf8 grep -oP 'MeshCentral v\K\d+\.\d+\.\d+' || true)
echo meshcentral_version=$meshcentral_version
docker image tag $image_name $image_repo:${meshcentral_version%.*}.x  #2.4.x
docker image tag $image_name $image_repo:${meshcentral_version%%.*}.x #2.x


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


#################################################
# remove untagged images
#################################################
# http://www.projectatomic.io/blog/2015/07/what-are-docker-none-none-images/
untagged_images=$(docker images -f "dangling=true" -q --no-trunc)
[[ -n $untagged_images ]] && docker rmi $untagged_images || true


#################################################
# display some image information
#################################################
echo ""
echo "IMAGE NAME"
echo "$image_name"
echo ""
docker images "$image_repo"
echo ""
docker history "$image_name"
