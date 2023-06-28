#!/bin/bash -e

echo -n "Prepare environment variables "

if [ ${RUNNING_PRODUCTION} -eq "1" ]; then
    ENVIRONMENT_VARIABLES["MAILER_FORCE_WHITELIST"]=false
else
    ENVIRONMENT_VARIABLES["MAILER_FORCE_WHITELIST"]=true
fi

# Webserver Deployment configuration files
ITERATOR=0

for key in "${!ENVIRONMENT_VARIABLES[@]}"; do
    if [ -z "${ENVIRONMENT_VARIABLES[$key]}" ]
    then
        echo "Variable '${key}' couldn't be set because it's empty"
    else
        # Webserver PHP-FPM deployment
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].name" ${key}
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].value" "\"${ENVIRONMENT_VARIABLES[${key}]}\""

        # Cron deployment
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/cron.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].name" ${key}
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/cron.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].value" "\"${ENVIRONMENT_VARIABLES[${key}]}\""

        # Environment configmap for cronjob
        ENV_LINE="        export ${key}='${ENVIRONMENT_VARIABLES[${key}]}'"
        echo "${ENV_LINE}" >> "${CONFIGURATION_TARGET_PATH}/configmap/cron-env.yaml"

        # Migration Job - First deploy
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/first-deploy/migrate-application.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].name" ${key}
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/first-deploy/migrate-application.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].value" "\"${ENVIRONMENT_VARIABLES[${key}]}\""

        # Migration Job - Continuous deploy
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/continuous-deploy/migrate-application.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].name" ${key}
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/continuous-deploy/migrate-application.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].value" "\"${ENVIRONMENT_VARIABLES[${key}]}\""

        ITERATOR=$(expr $ITERATOR + 1)
    fi
done
unset ENVIRONMENT_VARIABLES

# Storefront Deployment configuration files
ITERATOR=0
for key in ${!STOREFRONT_ENVIRONMENT_VARIABLES[@]}; do

    if [ -z ${STOREFRONT_ENVIRONMENT_VARIABLES[${key}]} ]
    then
        echo "Variable '${key}' couldn't be set because it's empty"
    else
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].name" ${key}
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].value" "\"${STOREFRONT_ENVIRONMENT_VARIABLES[${key}]}\""

        ITERATOR=$(expr $ITERATOR + 1)
    fi
done
unset STOREFRONT_ENVIRONMENT_VARIABLES

find ${CONFIGURATION_TARGET_PATH} -type f | xargs sed -i  's/nullPlaceholder//' # Remove nullPlaceholder from deployment files

# Add domains configuration to storefront container
for DOMAIN in ${DOMAINS[@]}; do
    BASENAME=${!DOMAIN}

    if [[ "${BASENAME}" == *"/"* ]]; then
        BASENAME=${BASENAME%%\/*} # Remove path from Domain if exists
    fi

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].name" "\"${DOMAIN}\""
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].value" "\"https://${BASENAME}/\""

    ITERATOR=$(expr $ITERATOR + 1)

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].name" "\"${DOMAIN/DOMAIN_HOSTNAME/PUBLIC_GRAPHQL_ENDPOINT_HOSTNAME}\""
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].value" "\"https://${BASENAME}/graphql/\""

    ITERATOR=$(expr $ITERATOR + 1)
done

yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].name" "\"INTERNAL_GRAPHQL_ENDPOINT\""
yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].env[${ITERATOR}].value" "\"http://webserver-php-fpm:8080/graphql/\""


echo -e "[${GREEN}OK${NO_COLOR}]"
