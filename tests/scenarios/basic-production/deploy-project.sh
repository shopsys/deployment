#!/bin/bash -e
SCENARIO_NAME="basic-production"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
export MCP_IP_WHITELIST="203.0.113.0/24,198.51.100.10/32"
ENABLE_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

DEFAULT_CONSUMERS=("email:email_transport:1")

case "$1" in
    "generate") run_merge; run_generate ;;
    *) echo "Usage: $0 generate"; exit 1 ;;
esac
