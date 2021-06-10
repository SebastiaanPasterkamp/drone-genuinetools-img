#!/bin/sh
# Based on https://github.com/banzaicloud/drone-kaniko.git

set -euo pipefail
export PATH=/usr/bin:$PATH

img --version

REGISTRY=${PLUGIN_REGISTRY:-index.docker.io}

if [ "${PLUGIN_USERNAME:-}" ] || [ "${PLUGIN_PASSWORD:-}" ]; then
    DOCKER_AUTH=`echo -n "${PLUGIN_USERNAME}:${PLUGIN_PASSWORD}" | base64 | tr -d "\n"`

    cat > /home/user/.docker/config.json <<DOCKERJSON
{
    "auths": {
        "${REGISTRY}": {
            "auth": "${DOCKER_AUTH}"
        }
    }
}
DOCKERJSON
fi

if [ "${PLUGIN_JSON_KEY:-}" ];then
    echo "${PLUGIN_JSON_KEY}" > /home/user/gcr.json
    export GOOGLE_APPLICATION_CREDENTIALS=/home/user/gcr.json
fi

DOCKERFILE=${PLUGIN_DOCKERFILE:-Dockerfile}
CONTEXT=${PLUGIN_CONTEXT:-$PWD}
LOG=${PLUGIN_LOG:-info}

if [[ -n "${PLUGIN_TARGET:-}" ]]; then
    TARGET="--target=${PLUGIN_TARGET}"
fi

if [[ "${PLUGIN_INSECURE_REGISTRY:-}" == "true" ]]; then
    INSECURE_REGISTRY="--insecure-registry"
fi

if [[ "${PLUGIN_CACHE:-}" != "true" ]]; then
    CACHE="--no-cache"
fi

if [ -n "${PLUGIN_CACHE_FROM:-}" ]; then
    CACHE_REPO="--cache-from=${PLUGIN_CACHE_FROM}"
fi

if [ -n "${PLUGIN_BUILD_ARGS:-}" ]; then
    BUILD_ARGS="--build-arg=${PLUGIN_BUILD_ARGS}"
fi

if [ -n "${PLUGIN_PLATFORM:-}" ]; then
    PLATFORM=$(
        echo "${PLUGIN_PLATFORM}" | tr ',' '\n' | while read platform; do
            echo "--platform=${platform} ";
        done
    )
fi

IMAGE=""
if [ -n "${PLUGIN_REGISTRY:-}" ] && [ -n "${PLUGIN_REPO:-}" ]; then
    IMAGE="${PLUGIN_REGISTRY}/${PLUGIN_REPO}"
fi

TAGS="--tag=${IMAGE}:latest"
# auto_tag, if set auto_tag: true, auto generate .tags file
# support format Major.Minor.Release or start with `v`
# docker tags: Major, Major.Minor, Major.Minor.Release and latest
if [[ "${PLUGIN_AUTO_TAG:-}" == "true" ]]; then
    TAG=$(echo "${DRONE_TAG:-}" |sed 's/^v//g')
    part=$(echo "${TAG}" |tr '.' '\n' |wc -l)
    # expect number
    echo ${TAG} | grep -E "[a-z-]" &> /dev/null && isNum=1 || isNum=0

    if [ ! -n "${TAG:-}" ];then
        TAGS="--tag=${IMAGE}:latest"
    elif [ ${isNum} -eq 1 -o ${part} -gt 3 ];then
        TAGS="--tag=${IMAGE}:${TAG} --tag=${IMAGE}:latest"
    else
        major=$(echo "${TAG}" |awk -F'.' '{print $1}')
        minor=$(echo "${TAG}" |awk -F'.' '{print $2}')
        release=$(echo "${TAG}" |awk -F'.' '{print $3}')

        major=${major:-0}
        minor=${minor:-0}
        release=${release:-0}

        TAGS="--tag=${IMAGE}:${major} --tag=${IMAGE}:${major}.${minor} --tag=${IMAGE}:${major}.${minor}.${release} --tag=${IMAGE}:latest"
    fi
elif [ -n "${PLUGIN_TAGS:-}" ]; then
    TAGS=$(
        echo "${PLUGIN_TAGS}" | tr ',' '\n' | while read tag; do
            echo "--tag=${IMAGE}:${tag} "
        done
    )
fi

echo "Building '${DOCKERFILE}' in '${CONTEXT}' as ${TAGS//--tag=/}"

/usr/bin/img \
    build \
    --file=${DOCKERFILE} \
    ${PLATFORM:-} \
    ${CACHE:-} \
    ${CACHE_REPO:-} \
    ${BUILD_ARGS:-} \
    ${TAGS} \
    ${CONTEXT}

echo "Pushing ${INSECURE_REGISTRY} ${TAGS//--tag=}"

echo "${TAGS//--tag=/}" | while read -d ' ' tag; do
    /usr/bin/img push "${INSECURE_REGISTRY:-}" "${tag}"
done
