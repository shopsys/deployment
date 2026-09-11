#!/bin/bash -e
SCENARIO_NAME="merge-phase-failure"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
ENABLE_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

# Guards the test runner itself: a failed merge phase must fail the scenario even though the generate phase would succeed
function merge() {
    run_merge
    echo "merge phase failed on purpose"
    exit 23
}

case "$1" in
    "merge") merge ;;
    "generate") run_generate ;;
    "deploy") run_generate; run_deploy ;;
    *) echo "Usage: $0 merge|generate|deploy"; exit 1 ;;
esac
