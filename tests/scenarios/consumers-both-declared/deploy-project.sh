#!/bin/bash -e
SCENARIO_NAME="consumers-both-declared"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
ENABLE_AUTOSCALING=true
ENABLE_CONSUMER_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

# As in project-base, the array is defined inside the merge function, so it is not visible to consumers.sh in the generate phase
function merge() {
    DEFAULT_CONSUMERS=("email:email_transport:1")
    run_merge
}

case "$1" in
    "merge") merge ;;
    "generate") run_generate ;;
    *) echo "Usage: $0 merge|generate"; exit 1 ;;
esac
