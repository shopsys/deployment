#!/bin/bash -e
SCENARIO_NAME="ttfb-http-auth"
source "$(dirname "$0")/../../lib/scenario-base.sh"

# Scenario-specific configuration
DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
ENABLE_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

DEFAULT_CONSUMERS=("email:email_transport:1")

# DOMAIN_HOSTNAME_2 is behind HTTP basic auth even in production - probes
# targeting this domain must have HTTP_AUTH_CREDENTIALS embedded into the URL.
FORCE_HTTP_AUTH_IN_PRODUCTION=(DOMAIN_HOSTNAME_2)

# TTFB probes target the HTTP-auth-protected domain — HTTP_AUTH_CREDENTIALS
# must be embedded into the probe URL (https://user:pass@host/...).
TTFB_PROBES_DOMAIN=DOMAIN_HOSTNAME_2
declare -A TTFB_PROBES=(
    ["Homepage"]=""
    ["Detail"]="/sample-product"
)

case "$1" in
    "generate") run_merge; run_generate ;;
    *) echo "Usage: $0 generate"; exit 1 ;;
esac
