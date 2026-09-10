#!/bin/bash -e
SCENARIO_NAME="development-with-cloudflare"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Development environment behind Cloudflare. Being non-production, HTTP basic auth is
# enabled automatically, which in turn generates the MCP ingress. This covers the
# Cloudflare + MCP case: the MCP ingress must stay free of basic auth, IP whitelisting
# and the Cloudflare server-snippet (server-scoped settings of the main ingress apply
# to the whole hostname) so external Bearer-token MCP clients stay reachable.
DOMAINS=(DOMAIN_HOSTNAME_1)
export RUNNING_PRODUCTION=0
export USING_CLOUDFLARE=1
export CLOUDFLARE_IPS="103.21.244.0/22,103.22.200.0/22,104.16.0.0/13"
export WHITELIST_IPS="10.0.0.0/8,192.168.0.0/16"
ENABLE_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

DEFAULT_CONSUMERS=()

case "$1" in
    "merge") run_merge ;;
    "generate") run_generate ;;
    *) echo "Usage: $0 merge|generate"; exit 1 ;;
esac
