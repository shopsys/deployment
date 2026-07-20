#!/bin/bash -e
SCENARIO_NAME="development-single-domain"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1)
export RUNNING_PRODUCTION=0
export WHITELIST_IPS="10.0.0.0/8,192.168.0.0/16"
# HTTP basic auth would normally generate the MCP ingress here - this covers the off switch
# (the default enabled behavior is covered by the development-with-cloudflare scenario)
export MCP_INGRESS_ENABLED=0
ENABLE_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

DEFAULT_CONSUMERS=()

case "$1" in
    "generate") run_merge; run_generate ;;
    *) echo "Usage: $0 generate"; exit 1 ;;
esac
