#!/bin/bash -e
SCENARIO_NAME="production-with-cloudflare"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
export USING_CLOUDFLARE=1
export CLOUDFLARE_IPS="103.21.244.0/22,103.22.200.0/22,104.16.0.0/13"

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
    ["feed-generator"]='0 */2 * * *'
)

DEFAULT_CONSUMERS=(
    "email:email_transport:2"
    "order:order_transport:3"
)

case "$1" in
    "generate") run_merge; run_generate ;;
    *) echo "Usage: $0 generate"; exit 1 ;;
esac
