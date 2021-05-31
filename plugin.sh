#!/bin/sh
# Based on https://github.com/banzaicloud/drone-kaniko.git

set -euo pipefail
export PATH=/usr/bin:$PATH

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
EXTRA_OPTS=""

if [[ -n "${PLUGIN_TARGET:-}" ]]; then
    TARGET="--target=${PLUGIN_TARGET}"
fi

if [[ "${PLUGIN_SKIP_TLS_VERIFY:-}" == "true" ]]; then
    EXTRA_OPTS="--insecure-registry=true"
fi

if [[ "${PLUGIN_CACHE:-}" == "false" ]]; then
    CACHE="--no-cache"
fi

if [ -n "${PLUGIN_CACHE_FROM:-}" ]; then
    CACHE_REPO="--cache-from=${PLUGIN_CACHE_FROM}"
fi

if [ -n "${PLUGIN_BUILD_ARGS:-}" ]; then
    BUILD_ARGS="--build-arg=${PLUGIN_BUILD_ARGS}"
fi

# auto_tag, if set auto_tag: true, auto generate .tags file
# support format Major.Minor.Release or start with `v`
# docker tags: Major, Major.Minor, Major.Minor.Release and latest
if [[ "${PLUGIN_AUTO_TAG:-}" == "true" ]]; then
    TAG=$(echo "${DRONE_TAG:-}" |sed 's/^v//g')
    part=$(echo "${TAG}" |tr '.' '\n' |wc -l)
    # expect number
    echo ${TAG} |grep -E "[a-z-]" &>/dev/null && isNum=1 || isNum=0

    if [ ! -n "${TAG:-}" ];then
        echo "latest" > .tags
    elif [ ${isNum} -eq 1 -o ${part} -gt 3 ];then
        echo "${TAG},latest" > .tags
    else
        major=$(echo "${TAG}" |awk -F'.' '{print $1}')
        minor=$(echo "${TAG}" |awk -F'.' '{print $2}')
        release=$(echo "${TAG}" |awk -F'.' '{print $3}')

        major=${major:-0}
        minor=${minor:-0}
        release=${release:-0}

        echo "${major},${major}.${minor},${major}.${minor}.${release},latest" > .tags
    fi
fi

/usr/bin/img \
    --context=${CONTEXT} \
    --dockerfile=${DOCKERFILE} \
    ${EXTRA_OPTS} \
    ${DESTINATIONS} \
    ${CACHE:-} \
    ${CACHE_REPO:-} \
    ${TARGET:-} \
    ${BUILD_ARGS:-}
