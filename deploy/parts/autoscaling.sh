#!/bin/bash -e

echo -n "Prepare Autoscaling "

assertVariable "BASE_PATH"
assertVariable "CONFIGURATION_TARGET_PATH"

if [[ "${ENABLE_AUTOSCALING:-true}" == "true" ]]; then
    if [ -z ${MIN_PHP_FPM_REPLICAS} ]; then
        MIN_PHP_FPM_REPLICAS=2
    fi

    if [ -z ${MAX_PHP_FPM_REPLICAS} ]; then
        MAX_PHP_FPM_REPLICAS=3
    fi

    if [ -z ${MIN_STOREFRONT_REPLICAS} ]; then
        MIN_STOREFRONT_REPLICAS=2
    fi

    if [ -z ${MAX_STOREFRONT_REPLICAS} ]; then
        MAX_STOREFRONT_REPLICAS=3
    fi

    yq e -i ".spec.minReplicas=${MIN_PHP_FPM_REPLICAS}" "${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml"
    yq e -i ".spec.maxReplicas=${MAX_PHP_FPM_REPLICAS}" "${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml"

    yq e -i ".spec.minReplicas=${MIN_STOREFRONT_REPLICAS}" "${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml"
    yq e -i ".spec.maxReplicas=${MAX_STOREFRONT_REPLICAS}" "${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml"
fi

yq e -i '
    .resources += [
      "../../horizontalPodAutoscaler.yaml",
      "../../horizontalStorefrontAutoscaler.yaml"
    ]
' "${CONFIGURATION_TARGET_PATH}/kustomize/webserver/kustomization.yaml"

echo -e "[${GREEN}OK${NO_COLOR}]"
