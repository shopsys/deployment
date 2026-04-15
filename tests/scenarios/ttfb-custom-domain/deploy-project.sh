#!/bin/bash -e
SCENARIO_NAME="ttfb-custom-domain"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
ENABLE_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

DEFAULT_CONSUMERS=("email:email_transport:1")

# TTFB probes target DOMAIN_HOSTNAME_2 ("www.example.com/cz") instead of the
# default. The probe paths intentionally exercise three formats:
#   ""              - no path (domain root, including the /cz suffix)
#   "/with-slash"   - path with leading slash
#   "without-slash" - path without leading slash (must be auto-prefixed)
TTFB_PROBES_DOMAIN=DOMAIN_HOSTNAME_2
declare -A TTFB_PROBES=(
    ["Homepage"]=""
    ["Detail"]="/sample-product"
    ["Category"]="sample-category"
)

case "$1" in
    "generate") run_merge; run_generate ;;
    *) echo "Usage: $0 generate"; exit 1 ;;
esac
