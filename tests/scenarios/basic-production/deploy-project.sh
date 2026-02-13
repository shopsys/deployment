#!/bin/bash -e
SCENARIO_NAME="basic-production"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

DEFAULT_CONSUMERS=("email:email_transport:1")

case "$1" in
    "generate") run_merge; run_generate ;;
    *) echo "Usage: $0 generate"; exit 1 ;;
esac
