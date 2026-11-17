#!/bin/bash -e
SCENARIO_NAME="consumers-orchestration-name-collision"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
ENABLE_AUTOSCALING=true
ENABLE_CONSUMER_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

# A hand-written consumer deployment in orchestration/kubernetes/deployments, added to the migrate-application kustomizations by the project
function merge() {
    mkdir -p "${BASE_PATH}/orchestration/kubernetes/deployments"
    sed -e 's|{{NAME}}|email|g' -e 's|{{TRANSPORT_NAMES}}|email_transport|g' -e 's|{{REPLICAS_COUNT}}|2|g' \
        "${BASE_PATH}/vendor/shopsys/deployment/kubernetes/manifest-templates/consumer.template.yaml" \
        > "${BASE_PATH}/orchestration/kubernetes/deployments/consumer-email.yaml"
    run_merge
    add_migrate_application_resource "../../../deployments/consumer-email.yaml"
}

case "$1" in
    "merge") merge ;;
    "generate") run_generate ;;
    "deploy") run_generate; run_deploy ;;
    *) echo "Usage: $0 merge|generate|deploy"; exit 1 ;;
esac
