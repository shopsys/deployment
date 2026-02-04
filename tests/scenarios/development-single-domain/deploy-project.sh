#!/bin/bash -e
SCENARIO_NAME="development-single-domain"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1)
export RUNNING_PRODUCTION=0
export WHITELIST_IPS="10.0.0.0/8,192.168.0.0/16"
ENABLE_AUTOSCALING=false

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

DEFAULT_CONSUMERS=()

case "$1" in
    "generate") run_merge; run_generate ;;
    *) echo "Usage: $0 generate"; exit 1 ;;
esac
