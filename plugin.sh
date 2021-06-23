#!/bin/sh
# Based on https://github.com/banzaicloud/drone-kaniko.git

set -euo pipefail
export PATH=/usr/bin:$PATH

img --version

DOCKER_CONFIG=${DOCKER_CONFIG:-/home/user/.docker/config.json}
DAEMON_CONFIG=${DAEMON_CONFIG:-/etc/docker/daemon.json}
REGISTRY=${PLUGIN_REGISTRY:-index.docker.io}

if [ "${PLUGIN_USERNAME:-}" ] || [ "${PLUGIN_PASSWORD:-}" ]; then
    mkdir -p $(dirname "${DOCKER_CONFIG}")
    DOCKER_AUTH=`echo -n "${PLUGIN_USERNAME}:${PLUGIN_PASSWORD}" | base64 | tr -d "\n"`
    echo "{ \"auths\": { \"${REGISTRY}\": { \"auth\": \"${DOCKER_AUTH}\" } } }" \
        >> $DOCKER_CONFIG
fi

if [ -n "${PLUGIN_REGISTRY_MIRRORS:-}" ] || [ -n "${PLUGIN_INSECURE_REGISTRIES:-}" ] ; then
    mkdir -p $(dirname "${DAEMON_CONFIG}")
    echo "{" > $DAEMON_CONFIG
    if [ "${PLUGIN_REGISTRY_MIRRORS:-}" ] ; then
        MIRRORS=$(
            SEP=""
            echo "${PLUGIN_REGISTRY_MIRRORS}" | tr ',' '\n' | while read mirror; do
                echo "${SEP}\"${mirror}\"";
                SEP=", "
            done
        )
        echo "  \"registry-mirrors\": [ ${MIRRORS} ]," \
            >> $DAEMON_CONFIG
    fi
    if [ "${PLUGIN_INSECURE_REGISTRIES:-}" ] ; then
        REGISTRIES=$(
            SEP=""
            echo "${PLUGIN_INSECURE_REGISTRIES}" | tr ',' '\n' | while read registry; do
                echo "${SEP}\"${registry}\"";
                SEP=", "
            done
        )
        echo "  \"insecure-registries\": [ ${REGISTRIES} ]," \
            >> $DAEMON_CONFIG
    fi
    # Add fake final entry, so the terminating ',' in the previous line is syntactically correct
    echo "  \"drone\": \"plugin\"" >> $DAEMON_CONFIG
    echo "}" >> $DAEMON_CONFIG
fi

if [ "${PLUGIN_JSON_KEY:-}" ];then
    echo "${PLUGIN_JSON_KEY}" > /home/user/gcr.json
    export GOOGLE_APPLICATION_CREDENTIALS=/home/user/gcr.json
fi

CONTEXT=${PLUGIN_CONTEXT:-${PWD}}
DOCKERFILE=${CONTEXT}/${PLUGIN_DOCKERFILE:-Dockerfile}
LOG=${PLUGIN_LOG:-info}

if [[ -n "${PLUGIN_TARGET:-}" ]]; then
    TARGET="--target=${PLUGIN_TARGET}"
fi

if [[ "${PLUGIN_INSECURE_REGISTRY:-}" == "true" ]]; then
    INSECURE_REGISTRY="--insecure-registry"
fi

if [[ "${PLUGIN_CACHE:-}" == "false" ]]; then
    CACHE="${CACHE:-} --no-cache"
fi

if [ -n "${PLUGIN_CACHE_FROM:-}" ]; then
    CACHE="${CACHE:-} --cache-from=${PLUGIN_CACHE_FROM}"
fi

if [ -n "${PLUGIN_CACHE_TO:-}" ]; then
    CACHE="${CACHE:-} --cache-to=${PLUGIN_CACHE_TO}"
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
            echo -n "--tag=${IMAGE}:${tag##*/} "
        done
    )
fi

echo "Building '${DOCKERFILE}' in '${CONTEXT}' as ${TAGS//--tag=/}"
echo "Platforms: ${PLATFORM:-}, Cache: ${CACHE:-}, Args: ${BUILD_ARGS:-}, Target: ${TARGET:-}"

/usr/bin/img \
    build \
    --file=${DOCKERFILE} \
    ${PLATFORM:-} \
    ${CACHE:-} \
    ${BUILD_ARGS:-} \
    ${TARGET:-} \
    ${TAGS} \
    ${CONTEXT}

echo "Pushing ${INSECURE_REGISTRY} ${TAGS//--tag=}"

echo -n "${TAGS//--tag=/}" | tr ' ' '\n' | while read tag; do
    /usr/bin/img push "${INSECURE_REGISTRY:-}" "${tag}"
done
