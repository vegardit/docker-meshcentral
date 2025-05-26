#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com)
# SPDX-FileContributor: Sebastian Thomschke
# SPDX-License-Identifier: Apache-2.0
# SPDX-ArtifactOfProjectHomePage: https://github.com/vegardit/docker-meshcentral

shared_lib="$(dirname "${BASH_SOURCE[0]}")/.shared"
[[ -e $shared_lib ]] || curl -sSfL "https://raw.githubusercontent.com/vegardit/docker-shared/v1/download.sh?_=$(date +%s)" | bash -s v1 "$shared_lib" || exit 1
# shellcheck disable=SC1091  # Not following: $shared_lib/lib/build-image-init.sh was not specified as input
source "$shared_lib/lib/build-image-init.sh"


#################################################
# declare image meta
#################################################
image_repo=${DOCKER_IMAGE_REPO:-vegardit/meshcentral}
base_image=${DOCKER_BASE_IMAGE:-node:lts-slim}

platforms="linux/amd64,linux/arm64/v8" #linux/arm/v7

declare -A image_meta=(
  [authors]="Vegard IT GmbH (vegardit.com)"
  [title]="$image_repo"
  [description]="Opinionated docker image to run a MeshCentral server to manage/access remote machines from within a browser"
  [source]="$(git config --get remote.origin.url)"
  [revision]="$(git rev-parse --short HEAD)"
  [version]="$(git rev-parse --short HEAD)"
  [created]="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
)

declare -a tags=()
tags+=("latest")


#################################################
# decide if multi-arch build
#################################################
if [[ ${DOCKER_PUSH:-} == "true" || ${DOCKER_PUSH_GHCR:-} == "true" ]]; then
  build_multi_arch="true"
fi


#################################################
# prepare docker
#################################################
run_step -- docker version

# https://github.com/docker/buildx/#building-multi-platform-images
run_step -- docker buildx version  # ensures buildx is enabled

export DOCKER_BUILDKIT=1
export DOCKER_CLI_EXPERIMENTAL=1 # prevents "docker: 'buildx' is not a docker command." in older Docker versions

if [[ ${build_multi_arch:-} == "true" ]]; then
  # Use a temporary local registry to work around Docker/Buildx/BuildKit quirks,
  # enabling us to build/test multiarch images locally before pushing.
  run_step -- start_docker_registry LOCAL_REGISTRY

  # Register QEMU emulators so Docker can run and build multi-arch images
  run_step "Install QEMU emulators" -- \
    docker run --privileged --rm ghcr.io/dockerhub-mirror/tonistiigi__binfmt --install all
fi

# https://docs.docker.com/build/buildkit/configure/#resource-limiting
echo "
[worker.oci]
  max-parallelism = 3
" | sudo tee /etc/buildkitd.toml

builder_name="bx-$(date +%s)-$RANDOM"
run_step "Configure buildx builder" -- docker buildx create \
  --name "$builder_name" \
  --bootstrap \
  --config /etc/buildkitd.toml \
  --driver-opt network=host `# required for buildx to access the temporary registry` \
  --driver docker-container \
  --driver-opt image=ghcr.io/dockerhub-mirror/moby__buildkit:latest
trap 'docker buildx rm --force "$builder_name"' EXIT


#################################################
# build the image
#################################################
image_name=image_repo:${tags[0]}

build_opts=(
  --file "image/Dockerfile"
  --builder "$builder_name"
  --progress=plain
  --pull
  # using the current date as value for BASE_LAYER_CACHE_KEY, i.e. the base layer cache (that holds system packages with security updates) will be invalidate once per day
  --build-arg BASE_LAYER_CACHE_KEY="$base_layer_cache_key"
  --build-arg BASE_IMAGE="$base_image"
  --build-arg GIT_BRANCH="${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
  --build-arg GIT_COMMIT_DATE="$(date -d "@$(git log -1 --format='%at')" --utc +'%Y-%m-%d %H:%M:%S UTC')"
  --build-arg INSTALL_SUPPORT_TOOLS="${INSTALL_SUPPORT_TOOLS:-0}"
)

for key in "${!image_meta[@]}"; do
  build_opts+=(--build-arg "OCI_${key}=${image_meta[$key]}")
  if [[ ${build_multi_arch:-} == "true" ]]; then
    build_opts+=(--annotation "index:org.opencontainers.image.${key}=${image_meta[$key]}")
  fi
done

if [[ ${build_multi_arch:-} == "true" ]]; then
  build_opts+=(--push)
  build_opts+=(--sbom=true) # https://docs.docker.com/build/metadata/attestations/sbom/#create-sbom-attestations
  build_opts+=(--platform "$platforms")
  build_opts+=(--tag "$LOCAL_REGISTRY/$image_name")
else
  build_opts+=(--output "type=docker,load=true")
  build_opts+=(--tag "$image_name")
fi

if [[ $OSTYPE == "cygwin" || $OSTYPE == "msys" ]]; then
  project_root=$(cygpath -w "$project_root")
fi

run_step "Building docker image [$image_name]..." -- \
  docker buildx build "${build_opts[@]}" "$project_root"


#################################################
# load image into local docker daemon for testing
#################################################
if [[ ${build_multi_arch:-} == "true" ]]; then
  run_step "Load image into local daemon for testing" @@ "
    docker pull '$LOCAL_REGISTRY/$image_name';
    docker tag '$LOCAL_REGISTRY/$image_name' '$image_name'
  "
fi


#################################################
# perform security audit
#################################################
if [[ ${DOCKER_AUDIT_IMAGE:-1} == "1" ]]; then
  run_step "Auditing docker image [$image_name]" -- \
    bash "$shared_lib/cmd/audit-image.sh" "$image_name"
fi


#################################################
# determine effective MeshCentral version
#################################################
echo
log INFO "Determining effective MeshCentral version of [$image_name]..."
# LC_ALL=en_US.utf8 -> workaround for "grep: -P supports only unibyte and UTF-8 locales"
# 2>/dev/null -> workaround for "write /dev/stdout: The pipe is being closed."
meshcentral_version=$(docker run --rm "$image_name" node node_modules/meshcentral --help 2>/dev/null | LC_ALL=en_US.utf8 grep -oP 'MeshCentral v\K\d+\.\d+\.\d+' | head -1 || true)
echo "meshcentral_version=$meshcentral_version"


#################################################
# extend tags
#################################################
tags+=("${meshcentral_version%.*}.x")  # :1.1.x
tags+=("${meshcentral_version%%.*}.x") # :1.x


#################################################
# push image
#################################################
function regctl() {
  run_step "regctl ${*}" -- \
    docker run --rm \
    -u "$(id -u):$(id -g)" -e HOME -v "$HOME:$HOME" \
    -v /etc/docker/certs.d:/etc/docker/certs.d:ro \
    --network host `# required to access the temporary registry` \
    ghcr.io/regclient/regctl:latest \
    --host "reg=$LOCAL_REGISTRY,tls=disabled" \
    "${@}"
}

if [[ ${DOCKER_PUSH:-} == "true" ]]; then
  for tag in "${tags[@]}"; do
    regctl image copy --referrers "$LOCAL_REGISTRY/$image_name" "docker.io/$image_repo:$tag"
  done
fi
if [[ ${DOCKER_PUSH_GHCR:-} == "true" ]]; then
  for tag in "${tags[@]}"; do
    regctl image copy --referrers "$LOCAL_REGISTRY/$image_name" "ghcr.io/$image_repo:$tag"
  done
fi
