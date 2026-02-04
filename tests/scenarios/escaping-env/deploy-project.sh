#!/bin/bash -e
SCENARIO_NAME="escaping-env"
source "$(dirname "$0")/../../lib/scenario-base.sh"

DOMAINS=(DOMAIN_HOSTNAME_1 DOMAIN_HOSTNAME_2)
export RUNNING_PRODUCTION=1
export FIRST_DEPLOY=0
ENABLE_AUTOSCALING=true

declare -A CRON_INSTANCES=(
    ["cron"]='*/5 * * * *'
)

DEFAULT_CONSUMERS=(
    "email:email_transport:1"
)

VARS+=(SENTRY_RELEASE)
ENVIRONMENT_VARIABLES["SENTRY_RELEASE"]="${SENTRY_RELEASE}"
STOREFRONT_ENVIRONMENT_VARIABLES["SENTRY_RELEASE"]="${SENTRY_RELEASE}"

case "$1" in
    "generate") run_merge; run_generate ;;
    *) echo "Usage: $0 generate"; exit 1 ;;
esac
