#!/bin/bash -e
SCENARIO_NAME="consumers-invalid-fields"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
ENABLE_AUTOSCALING=true
ENABLE_CONSUMER_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

case "$1" in
    "merge") run_merge ;;
    "generate") run_generate ;;
    *) echo "Usage: $0 merge|generate"; exit 1 ;;
esac
