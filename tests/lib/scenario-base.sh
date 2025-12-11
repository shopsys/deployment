#!/bin/bash
# Base configuration shared by all test scenarios

# Path setup - uses exported paths from test runner or defaults
BASE_PATH="${BASE_PATH:-$(realpath "$(dirname "$0")/../../tmp/${SCENARIO_NAME}")}"
CONFIGURATION_TARGET_PATH="${CONFIGURATION_TARGET_PATH:-${BASE_PATH}/var/deployment/kubernetes}"
BASIC_AUTH_PATH="${BASIC_AUTH_PATH:-${BASE_PATH}/deploy/basicHttpAuth}"
DEPLOY_TARGET_PATH="${DEPLOY_TARGET_PATH:-${BASE_PATH}/var/deployment/deploy}"

# Default environment variables (same across most scenarios)
declare -A ENVIRONMENT_VARIABLES=(
    ["APP_SECRET"]="${APP_SECRET}"
    ["DATABASE_HOST"]="${POSTGRES_DATABASE_IP_ADDRESS}"
    ["DATABASE_NAME"]="${PROJECT_NAME}"
    ["DATABASE_PORT"]="${POSTGRES_DATABASE_PORT}"
    ["DATABASE_USER"]="${PROJECT_NAME}"
    ["DATABASE_PASSWORD"]="${POSTGRES_DATABASE_PASSWORD}"
    ["S3_ENDPOINT"]="${S3_ENDPOINT}"
    ["S3_ACCESS_KEY"]="${PROJECT_NAME}"
    ["S3_SECRET"]="${S3_SECRET}"
    ["S3_BUCKET_NAME"]="${PROJECT_NAME}"
    ["ELASTICSEARCH_HOST"]="${ELASTICSEARCH_URLS}"
    ["ELASTIC_SEARCH_INDEX_PREFIX"]="${PROJECT_NAME}"
    ["REDIS_PREFIX"]="${PROJECT_NAME}"
    ["MAILER_DSN"]="${MAILER_DSN}"
    ["TRUSTED_PROXY"]="10.0.0.0/8"
    ["MESSENGER_TRANSPORT_DSN"]="${MESSENGER_TRANSPORT_DSN}"
)

declare -A STOREFRONT_ENVIRONMENT_VARIABLES=()

# Default VARS needed for kubernetes-variables.sh
VARS=(
    TAG
    STOREFRONT_TAG
    PROJECT_NAME
    BASE_PATH
    RABBITMQ_DEFAULT_USER
    RABBITMQ_DEFAULT_PASS
    RABBITMQ_IP_WHITELIST
)

# Common exports
export FIRST_DEPLOY=0
export DISPLAY_FINAL_CONFIGURATION=0

function run_generate() {
    source "${DEPLOY_TARGET_PATH}/functions.sh"
    source "${DEPLOY_TARGET_PATH}/parts/domains.sh"
    source "${DEPLOY_TARGET_PATH}/parts/domain-rabbitmq-management.sh"
    source "${DEPLOY_TARGET_PATH}/parts/environment-variables.sh"
    source "${DEPLOY_TARGET_PATH}/parts/kubernetes-variables.sh"
    source "${DEPLOY_TARGET_PATH}/parts/cron.sh"
    source "${DEPLOY_TARGET_PATH}/parts/autoscaling.sh"
}

function run_merge() {
    source "${BASE_PATH}/vendor/shopsys/deployment/deploy/functions.sh"
    merge_configuration
    create_consumer_manifests "${DEFAULT_CONSUMERS[@]}"
}
