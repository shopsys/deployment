#!/bin/bash

assertVariable "BASE_PATH"
assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "FIRST_DEPLOY"
assertVariable "DISPLAY_FINAL_CONFIGURATION"
assertVariable "PROJECT_NAME"
assertVariable "DOMAIN_HOSTNAME_1"

assertVariable "DEPLOY_REGISTER_USER"
assertVariable "DEPLOY_REGISTER_PASSWORD"

assertVariable "BASIC_AUTH_PATH"
assertVariable "ENABLE_AUTOSCALING"
assertVariable "RUNNING_PRODUCTION"
FIRST_DEPLOY_LOAD_DEMO_DATA=${FIRST_DEPLOY_LOAD_DEMO_DATA:-0}

echo "Prepare namespace to run project:"

slack_notification "start"

echo -n "    Create namespace "
runCommand "SKIP" "kubectl create namespace ${PROJECT_NAME}"

echo -n "    Delete secret for docker registry "
runCommand "SKIP" "kubectl delete secret dockerregistry -n ${PROJECT_NAME}"

echo -n "    Create new secret for docker registry "
if [ "${GCLOUD_DEPLOY}" = "true" ]; then
    runCommand "ERROR" "kubectl create secret docker-registry dockerregistry --docker-server=eu.gcr.io --docker-username _json_key --docker-email ${GCLOUD_CONTAINER_REGISTRY_EMAIL} --docker-password='${GCLOUD_CONTAINER_REGISTRY_ACCOUNT}' -n ${PROJECT_NAME}"
else
    runCommand "ERROR" "kubectl create secret docker-registry dockerregistry --docker-server=${CI_REGISTRY} --docker-username=${DEPLOY_REGISTER_USER} --docker-password=${DEPLOY_REGISTER_PASSWORD} -n ${PROJECT_NAME}"
fi

if [ ${RUNNING_PRODUCTION} -eq "0" ] || [ ${#FORCE_HTTP_AUTH_IN_PRODUCTION[@]} -ne "0" ]; then
    echo -n "    Create or update secret for http auth "
    runCommand "ERROR" "kubectl create secret generic http-auth --from-file=auth=${BASIC_AUTH_PATH} -n ${PROJECT_NAME} --dry-run -o yaml | kubectl apply -f -"
fi

IS_FE_API_SECRET_GENERATED=$(kubectl -n ${PROJECT_NAME} describe secrets/fe-api-keys > /dev/null 2>&1)$? || true

if [ "${IS_FE_API_SECRET_GENERATED}" -ne "0" ]; then
    echo -n "    Create Private Key for FE API "
    runCommand "ERROR" "openssl genrsa -out \"${BASE_PATH}/var/private.key\""
    echo -n "    Create Public Key for FE API "
    runCommand "ERROR" "openssl rsa -in \"${BASE_PATH}/var/private.key\" -pubout -out \"${BASE_PATH}/var/public.key\""
    echo -n "    Create secret with generated keys for FE API "
    runCommand "ERROR" "kubectl create secret generic fe-api-keys --from-file=private.key=\"${BASE_PATH}/var/private.key\" --from-file=public.key=\"${BASE_PATH}/var/public.key\" -n ${PROJECT_NAME}"
fi

if [ "${RUNNING_PRODUCTION}" -eq "0" ] || [ "${DOWNSCALE_RESOURCE:-0}" -eq "1" ]; then
    echo -n "    Replace pods CPU requests to minimum (for Devel cluster only) "

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].resources.requests.cpu" "0.01"
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml" "spec.template.spec.containers[0].resources.requests.cpu" "0.01"
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml" "spec.template.spec.containers[1].resources.requests.cpu" "0.01"
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/redis.yaml" "spec.template.spec.containers[1].resources.requests.cpu" "0.01"
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/rabbitmq.yaml" "spec.template.spec.containers[0].resources.requests.cpu" "0.01"

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml" "spec.template.spec.containers[0].resources.requests.memory" "100Mi"
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/redis.yaml" "spec.template.spec.containers[1].resources.requests.memory" "100Mi"

    echo -e "[${GREEN}OK${NO_COLOR}]"
else
    if [ -v PHP_FPM_CPU_REQUEST ] || [ -v STOREFRONT_CPU_REQUEST ]; then
        echo -n "    Replace pods CPU requests "

        if [ -v PHP_FPM_CPU_REQUEST ]; then
            yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml" "spec.template.spec.containers[0].resources.requests.cpu" "${PHP_FPM_CPU_REQUEST}"
        fi

        if [ -v STOREFRONT_CPU_REQUEST ]; then
            yq write --inplace "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml" "spec.template.spec.containers[0].resources.requests.cpu" "${STOREFRONT_CPU_REQUEST}"
        fi

        echo -e "[${GREEN}OK${NO_COLOR}]"
    fi
fi

DEPLOYED_CRON_POD=$(kubectl get pods --namespace=${PROJECT_NAME} --field-selector=status.phase=Running -l app=cron -o=jsonpath='{.items[?(@.status.containerStatuses[0].state.running)].metadata.name}') || true

if [[ -n ${DEPLOYED_CRON_POD} ]]; then
    echo -n "Lock crons to prevent run next iteration "
    runCommand "ERROR" "kubectl exec -t --namespace=${PROJECT_NAME} ${DEPLOYED_CRON_POD} -- bash -c \"./phing -S cron-lock > /dev/null 2>&1 & disown\""

    echo -n "Waiting until all cron instances are done "
    runCommand "ERROR" "kubectl exec --namespace=${PROJECT_NAME} ${DEPLOYED_CRON_POD} -- ./phing -S cron-watch"
fi

echo "Migrate Application (database migrations, elasticsearch migrations, ...):"

echo -n "    Delete previous migration pod "
runCommand "SKIP" "kubectl delete job/migrate-application --namespace=${PROJECT_NAME}"

if [ $FIRST_DEPLOY -eq "0" ]; then
    KUSTOMIZE_FOLDER="continuous-deploy"
else
    KUSTOMIZE_FOLDER="first-deploy"
    if [ ${FIRST_DEPLOY_LOAD_DEMO_DATA} -eq "1" ]; then
        KUSTOMIZE_FOLDER="first-deploy-with-demo-data"
    fi
fi

if [ $DISPLAY_FINAL_CONFIGURATION -eq "1" ]; then
    echo -n "    Show configuration "
    runCommand "ERROR" "kustomize build --load_restrictor none \"${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/${KUSTOMIZE_FOLDER}\""

    echo ""
    echo -e "section_start:`date +%s`:migrate_application_section\r\e[0K Configuration"
    echo "${LAST_COMMAND_OUTPUT}"
    echo -e "section_end:`date +%s`:migrate_application_section\r\e[0K"
    echo ""
fi

echo -n "    Apply configuration "
runCommand "ERROR" "kustomize build --load_restrictor none \"${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/${KUSTOMIZE_FOLDER}\" | kubectl apply -f -"

echo -n "    Waiting for migrate application "

MIGRATION_COMPLETE_EXIT_CODE=1
MIGRATION_FAILED_EXIT_CODE=1

while [[ ${MIGRATION_COMPLETE_EXIT_CODE} -eq 1 ]] && [[ ${MIGRATION_FAILED_EXIT_CODE} -eq 1 ]]; do
    sleep 5
    MIGRATION_FAILED_EXIT_CODE=$(kubectl wait --for=condition=failed job/migrate-application --timeout=0 --namespace=${PROJECT_NAME} > /dev/null 2>&1)$? || true
    MIGRATION_COMPLETE_EXIT_CODE=$(kubectl wait --for=condition=complete job/migrate-application --timeout=0 --namespace=${PROJECT_NAME} > /dev/null 2>&1)$? || true
done

if [ ${MIGRATION_COMPLETE_EXIT_CODE} -eq 1 ]; then
    echo -e "[${RED}ERROR${NO_COLOR}]"

    echo -n "Restore previous cron container "
    runCommand "SKIP" "kubectl delete pod --namespace=${PROJECT_NAME} ${DEPLOYED_CRON_POD}"

    RUNNING_WEBSERVER_PHP_FPM_POD=$(kubectl get pods --namespace=${PROJECT_NAME} --field-selector=status.phase=Running -l app=webserver-php-fpm -o=jsonpath='{.items[0].metadata.name}')

    echo -n "Disable Maintenance page if exists "
    runCommand "SKIP" "kubectl exec ${RUNNING_WEBSERVER_PHP_FPM_POD} --namespace=${PROJECT_NAME} -- ./phing maintenance-off"

    echo ""
    echo -e "section_start:`date +%s`:migrate_application_logs_section\r\e[0KLogs from migration application"
    kubectl logs job/migrate-application --namespace=${PROJECT_NAME}
    echo -e "section_end:`date +%s`:migrate_application_logs_section\r\e[0K"
    slack_notification "error"
    exit 1
else
    echo -e "[${GREEN}OK${NO_COLOR}]"

    echo ""
    echo -e "section_start:`date +%s`:migrate_application_logs_section\r\e[0KLogs from migration application"
    kubectl logs job/migrate-application --namespace=${PROJECT_NAME}
    echo -e "section_end:`date +%s`:migrate_application_logs_section\r\e[0K"
    echo ""

    echo -n "Deploy new cron container "
    runCommand "ERROR" "kustomize build --load_restrictor none \"${CONFIGURATION_TARGET_PATH}/kustomize/cron\" | kubectl apply -f -"
fi

echo "Deploy new Webserver and PHP-FPM container:"

if [ $DISPLAY_FINAL_CONFIGURATION -eq "1" ]; then
    echo -n "    Show PHP-FPM container configuration with Storefront"
    runCommand "ERROR" "kustomize build --load_restrictor none \"${CONFIGURATION_TARGET_PATH}/kustomize/webserver\""

    echo ""
    echo -e "section_start:`date +%s`:deploy_php_fpm_section\r\e[0K Show PHP-FPM configuration"
    echo "${LAST_COMMAND_OUTPUT}"
    echo -e "section_end:`date +%s`:deploy_php_fpm_section\r\e[0K"
    echo ""
fi

if [ ${ENABLE_AUTOSCALING} = true ]; then
    echo -n "    Delete previous Horizontal pod autoscaler for Backend "
    runCommand "SKIP" "kubectl delete hpa webserver-php-fpm --namespace=${PROJECT_NAME}"

    echo -n "    Delete previous Horizontal pod autoscaler for Storefront "
    runCommand "SKIP" "kubectl delete hpa storefront --namespace=${PROJECT_NAME}"
fi

echo -n "    Deploy Webserver and PHP-FPM container with Storefront"
runCommand "ERROR" "kustomize build --load_restrictor none  \"${CONFIGURATION_TARGET_PATH}/kustomize/webserver\" | kubectl apply -f -"

echo -n "    Waiting for start new PHP-FPM and Storefront container (In case of fail you need to manually check what is state of application)"
runCommand "ERROR" "kubectl rollout status --namespace=${PROJECT_NAME} deployment/webserver-php-fpm deployment/storefront --watch"

if [ ${ENABLE_AUTOSCALING} = true ]; then
    echo -n "    Deploy Horizontal pod autoscaler for Backend "

    if [ ${RUNNING_PRODUCTION} -eq "0" ]; then
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml" spec.minReplicas 2
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml" spec.maxReplicas 2
    fi

    runCommand "ERROR" "kubectl apply -f ${CONFIGURATION_TARGET_PATH}/horizontalPodAutoscaler.yaml"

    echo -n "    Deploy Horizontal pod autoscaler for Storefront "

    if [ ${RUNNING_PRODUCTION} -eq "0" ]; then
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml" spec.minReplicas 2
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml" spec.maxReplicas 2
    fi

    runCommand "ERROR" "kubectl apply -f ${CONFIGURATION_TARGET_PATH}/horizontalStorefrontAutoscaler.yaml"
fi

RUNNING_WEBSERVER_PHP_FPM_POD=$(kubectl get pods --namespace=${PROJECT_NAME} --field-selector=status.phase=Running -l app=webserver-php-fpm -o=jsonpath='{.items[?(@.status.containerStatuses[0].state.running)].metadata.name}')

echo -n "Disable maintenance page "
runCommand "ERROR" "kubectl exec ${RUNNING_WEBSERVER_PHP_FPM_POD} --namespace=${PROJECT_NAME} -- ./phing maintenance-off"

echo -n "Clean old redis keys "
runCommand "FAILED" "kubectl exec ${RUNNING_WEBSERVER_PHP_FPM_POD} --namespace=${PROJECT_NAME} -- ./phing clean-redis-old"

echo -n "Clean storefront cache (queries and translations) "
runCommand "FAILED" "kubectl exec ${RUNNING_WEBSERVER_PHP_FPM_POD} --namespace=${PROJECT_NAME} -- ./phing clean-redis-storefront"

if [ -z ${DISABLE_WEBSITE_RUNNING_CHECK} ]; then
    DISABLE_WEBSITE_RUNNING_CHECK=false
fi


function checkDomainIsRunning() {
    local domainHostname=$1
    echo -n "Check if website is running (${domainHostname}) "

    if [ ${RUNNING_PRODUCTION} -eq "1" ] && ! containsElement ${domainHostname} ${FORCE_HTTP_AUTH_IN_PRODUCTION[@]}; then
        CURL_RETURN_CODE=$(curl -L -s -o /dev/null -w "%{http_code}" https://${domainHostname})
    else
        if [ -z ${HTTP_AUTH_CREDENTIALS} ]; then
            HTTP_AUTH_CREDENTIALS="username:password"
        fi

        CURL_RETURN_CODE=$(curl --user ${HTTP_AUTH_CREDENTIALS} -L -s -o /dev/null -w "%{http_code}" https://${domainHostname})
    fi

    if [ ${CURL_RETURN_CODE} -eq "200" ]; then
        echo -e "[${GREEN}OK${NO_COLOR}]"
    else
        if [ ${CURL_RETURN_CODE} -eq "401" ]; then
            echo -e "[${YELLOW}SKIP${NO_COLOR}]"
            echo ""
            echo "URL could not be checked due to custom HTTP auth. Please check URL manually: https://${domainHostname}"
        else
            echo -e "[${RED}ERROR${NO_COLOR}]"
            slack_notification "error"
            exit 1
        fi
    fi
}

if [ ${DISABLE_WEBSITE_RUNNING_CHECK} = false ]; then
    for domain in "${DOMAINS[@]}"; do
        domainHostname="${!domain}"
        checkDomainIsRunning "$domainHostname"
    done
fi

slack_notification "end"
