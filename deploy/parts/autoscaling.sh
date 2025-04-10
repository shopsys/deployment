#!/bin/bash -e

echo -n "Prepare Autoscaling "

assertVariable "BASE_PATH"
assertVariable "CONFIGURATION_TARGET_PATH"

if [ -z ${ENABLE_AUTOSCALING} ]; then
    ENABLE_AUTOSCALING=false
fi

if [ ${ENABLE_AUTOSCALING} = true ]; then
    if [ -z ${MIN_PHP_FPM_REPLICAS} ]; then
        MIN_PHP_FPM_REPLICAS=2
    fi

    if [ -z ${MAX_PHP_FPM_REPLICAS} ]; then
        MAX_PHP_FPM_REPLICAS=2
    fi

    if [ -z ${MIN_STOREFRONT_REPLICAS} ]; then
        MIN_STOREFRONT_REPLICAS=2
    fi

    if [ -z ${MAX_STOREFRONT_REPLICAS} ]; then
        MAX_STOREFRONT_REPLICAS=2
    fi

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml" spec.minReplicas "${MIN_PHP_FPM_REPLICAS}"
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml" spec.maxReplicas "${MAX_PHP_FPM_REPLICAS}"

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml" spec.minReplicas "${MIN_STOREFRONT_REPLICAS}"
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml" spec.maxReplicas "${MAX_STOREFRONT_REPLICAS}"
fi


echo -e "[${GREEN}OK${NO_COLOR}]"
