#!/bin/bash -e

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
NO_COLOR='\e[39m'

function assertVariable() {
    var="$1"
    if [ -n "${!var}" ]; then
        return
    else
        echo "Variable $1 is not set"
        return 2
    fi
}

function containsElement () {
    local e match="$1"
    shift
    for e; do
        echo $match | grep -qi ^$e \
        && return 0
    done
    return 1
}

function runCommand() {
    if LAST_COMMAND_OUTPUT=$(eval "${2} 2>&1" 2>&1)
    then
        echo -e "[${GREEN}OK${NO_COLOR}]"
    else
        if [ $1 == "ERROR" ]; then
            echo -e "[${RED}ERROR${NO_COLOR}]"
            echo ""
            echo "${LAST_COMMAND_OUTPUT}"
            exit 1
        else
            echo -e "[${YELLOW}${1}${NO_COLOR}]"
        fi
    fi
}

function merge_configuration() {
    BASE_SCRIPT_PATH="${BASE_PATH}/vendor/shopsys/deployment/kubernetes"
    BASE_DEPLOYMENT_PATH="${BASE_PATH}/vendor/shopsys/deployment/deploy"
    OVERRIDEN_SCRIPT_PATH="${BASE_PATH}/orchestration/kubernetes"

    rm -rf "${CONFIGURATION_TARGET_PATH}"
    mkdir -p "${CONFIGURATION_TARGET_PATH}"

    cp -R "${BASE_SCRIPT_PATH}/." "${CONFIGURATION_TARGET_PATH}/"
    if [[ -d "${OVERRIDEN_SCRIPT_PATH}" ]]; then
        cp -R "${OVERRIDEN_SCRIPT_PATH}/." "${CONFIGURATION_TARGET_PATH}/"
    fi

    rm -rf "${DEPLOY_TARGET_PATH}"
    mkdir -p "${DEPLOY_TARGET_PATH}"

    cp -R "${BASE_DEPLOYMENT_PATH}/." "${DEPLOY_TARGET_PATH}/"
}

function find_file() {
    path=${1}
    filename=${2}
    is_dist=${3:-0}

    if [ ${is_dist} -eq 1 ];
    then
        echo "$(find "${path}" -type f -name "${filename}.yml.dist" -o -name "${filename}.yaml.dist")"
    else
        echo "$(find "${path}" -type f -name "${filename}.yml" -o -name "${filename}.yaml")"
    fi
}

function remove_dist() {
    echo ${1%.*}
}

function create_consumer_manifests() {
    local DEFAULT_CONSUMERS="$1"

    TEMPLATE_PATH="${CONFIGURATION_TARGET_PATH}/manifest-templates/consumer.template.yaml"

    for CONSUMER in "${DEFAULT_CONSUMERS[@]}"; do
        IFS=":" read -r NAME TRANSPORT_NAMES REPLICAS_COUNT <<< "$CONSUMER"

        CONSUMER_MANIFEST_PATH="${CONFIGURATION_TARGET_PATH}/deployments/consumer-${NAME}.yaml"

        cp "${TEMPLATE_PATH}" "${CONSUMER_MANIFEST_PATH}"

        sed -i "s|{{NAME}}|${NAME}|g" "${CONSUMER_MANIFEST_PATH}"
        sed -i "s|{{TRANSPORT_NAMES}}|${TRANSPORT_NAMES}|g" "${CONSUMER_MANIFEST_PATH}"
        sed -i "s|{{REPLICAS_COUNT}}|${REPLICAS_COUNT}|g" "${CONSUMER_MANIFEST_PATH}"

        sed -i "/resources:/a\    - ../../../deployments/consumer-${NAME}.yaml" "${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/continuous-deploy/kustomization.yaml"
    done
}
