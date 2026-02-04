#!/bin/bash -e

patch_rollout() {
    local file="$1" min_replicas="$2"

    if (( min_replicas >= 4 )); then
        yq e -i ".spec.strategy.rollingUpdate.maxUnavailable=25%" "$file"
    fi

    if (( min_replicas >= 6 )); then
        yq e -i ".spec.strategy.rollingUpdate.maxSurge=25%" "$file"
    fi
}

assertVariable "BASE_PATH"
assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "RUNNING_PRODUCTION"

if [[ "${ENABLE_AUTOSCALING:-false}" == "true" ]]; then
    echo -n "Prepare Autoscaling "

    MIN_PHP_FPM_REPLICAS="${MIN_PHP_FPM_REPLICAS:-2}"
    MAX_PHP_FPM_REPLICAS="${MAX_PHP_FPM_REPLICAS:-3}"
    MIN_STOREFRONT_REPLICAS="${MIN_STOREFRONT_REPLICAS:-2}"
    MAX_STOREFRONT_REPLICAS="${MAX_STOREFRONT_REPLICAS:-3}"

    if [[ "${RUNNING_PRODUCTION}" -eq 0 || "${DOWNSCALE_RESOURCE:-0}" -eq 1 ]]; then
        MIN_PHP_FPM_REPLICAS=2
        MAX_PHP_FPM_REPLICAS=2
        MIN_STOREFRONT_REPLICAS=2
        MAX_STOREFRONT_REPLICAS=2
    fi

    yq e -i ".spec.minReplicas=${MIN_PHP_FPM_REPLICAS}" "${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml"
    yq e -i ".spec.maxReplicas=${MAX_PHP_FPM_REPLICAS}" "${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml"

    yq e -i ".spec.minReplicas=${MIN_STOREFRONT_REPLICAS}" "${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml"
    yq e -i ".spec.maxReplicas=${MAX_STOREFRONT_REPLICAS}" "${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml"

    patch_rollout "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml" "${MIN_PHP_FPM_REPLICAS}"
    patch_rollout "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "${MIN_STOREFRONT_REPLICAS}"

    yq e -i '
        .resources += [
          "../../horizontalPodAutoscaler.yaml",
          "../../horizontalStorefrontAutoscaler.yaml"
        ]
    ' "${CONFIGURATION_TARGET_PATH}/kustomize/webserver/kustomization.yaml"

    echo -e "[${GREEN}OK${NO_COLOR}]"
fi
