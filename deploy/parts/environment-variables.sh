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
        # Consumer deployments
        for CONSUMER_FILE in "${CONFIGURATION_TARGET_PATH}/deployments/"consumer-*.yaml; do
            if [ -f "$CONSUMER_FILE" ]; then
                yq e -i "
                      .spec.template.spec.containers[0].env[${ITERATOR}] = {
                        \"name\": \"${key}\",
                        \"value\": \"${ENVIRONMENT_VARIABLES[$key]}\"
                      }
                    " "${CONSUMER_FILE}"
            fi
        done

        # Webserver PHP-FPM deployment
        yq e -i "
          .spec.template.spec.containers[0].env[${ITERATOR}] = {
            \"name\": \"${key}\",
            \"value\": \"${ENVIRONMENT_VARIABLES[$key]}\"
          }
        " "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml"

        # Webserver PHP-FPM warmup container
        yq e -i "
          .spec.template.spec.initContainers[1].env[${ITERATOR}] = {
            \"name\": \"${key}\",
            \"value\": \"${ENVIRONMENT_VARIABLES[$key]}\"
          }
        " "${CONFIGURATION_TARGET_PATH}/deployments/webserver-php-fpm.yaml"

        # Cron deployment
        yq e -i "
          .spec.template.spec.containers[0].env[${ITERATOR}] = {
            \"name\": \"${key}\",
            \"value\": \"${ENVIRONMENT_VARIABLES[$key]}\"
          }
        " "${CONFIGURATION_TARGET_PATH}/deployments/cron.yaml"

        # Environment configmap for cronjob
        ENV_LINE="        export ${key}='${ENVIRONMENT_VARIABLES[${key}]}'"
        echo "${ENV_LINE}" >> "${CONFIGURATION_TARGET_PATH}/configmap/cron-env.yaml"

        # Migration Job - First deploy
        yq e -i "
          .spec.template.spec.containers[0].env[${ITERATOR}] = {
            \"name\": \"${key}\",
            \"value\": \"${ENVIRONMENT_VARIABLES[$key]}\"
          }
        " "${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/first-deploy/migrate-application.yaml"

        # Migration Job - First deploy with demo data
        yq e -i "
          .spec.template.spec.containers[0].env[${ITERATOR}] = {
            \"name\": \"${key}\",
            \"value\": \"${ENVIRONMENT_VARIABLES[$key]}\"
          }
        " "${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/first-deploy-with-demo-data/migrate-application.yaml"

        # Migration Job - Continuous deploy
        yq e -i "
          .spec.template.spec.containers[0].env[${ITERATOR}] = {
            \"name\": \"${key}\",
            \"value\": \"${ENVIRONMENT_VARIABLES[$key]}\"
          }
        " "${CONFIGURATION_TARGET_PATH}/kustomize/migrate-application/continuous-deploy/migrate-application.yaml"

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
        yq e -i "
          .spec.template.spec.containers[0].env[${ITERATOR}] = {
            \"name\": \"${key}\",
            \"value\": \"${STOREFRONT_ENVIRONMENT_VARIABLES[$key]}\"
          }
        " "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml"

        ITERATOR=$(expr $ITERATOR + 1)
    fi
done
unset STOREFRONT_ENVIRONMENT_VARIABLES

find ${CONFIGURATION_TARGET_PATH} -type f | xargs sed -i  's/nullPlaceholder//' # Remove nullPlaceholder from deployment files

# Add domains configuration to storefront container
for DOMAIN in ${DOMAINS[@]}; do
    BASENAME=${!DOMAIN}

    yq e -i "
      .spec.template.spec.containers[0].env[${ITERATOR}] = {
        \"name\": \"${DOMAIN}\",
        \"value\": \"https://${BASENAME}/\"
      }
    " "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml"

    ITERATOR=$(expr $ITERATOR + 1)

    yq e -i "
      .spec.template.spec.containers[0].env[${ITERATOR}] = {
        \"name\": \"${DOMAIN/DOMAIN_HOSTNAME/PUBLIC_GRAPHQL_ENDPOINT_HOSTNAME}\",
        \"value\": \"https://${BASENAME}/graphql/\"
      }
    " "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml"

    ITERATOR=$(expr $ITERATOR + 1)
done

yq e -i "
  .spec.template.spec.containers[0].env[${ITERATOR}] = {
    \"name\": \"INTERNAL_ENDPOINT\",
    \"value\": \"http://webserver-php-fpm:8080/\"
  }
" "${CONFIGURATION_TARGET_PATH}/deployments/storefront.yaml"


echo -e "[${GREEN}OK${NO_COLOR}]"
