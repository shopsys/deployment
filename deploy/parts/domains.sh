#!/bin/bash -e

echo -n "Prepare Domains "

assertVariable "BASE_PATH"
assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "DOMAINS"
assertVariable "RUNNING_PRODUCTION"

DOMAINS_URLS_DIST_FILEPATH="$(find_file "${BASE_PATH}/config" "domains_urls" 1)"
DOMAINS_URLS_FILEPATH="$(remove_dist "${DOMAINS_URLS_DIST_FILEPATH}")"

cp "${DOMAINS_URLS_DIST_FILEPATH}" "${DOMAINS_URLS_FILEPATH}"

if [ -z "${FORCE_HTTP_AUTH_IN_PRODUCTION}" ]; then
  FORCE_HTTP_AUTH_IN_PRODUCTION=()
fi

# Global switch to indicate if site is using Cloudflare (default: disabled)
USING_CLOUDFLARE=${USING_CLOUDFLARE:-0}

# Global switch to disable publishing of the MCP ingress without HTTP basic auth (default: enabled)
MCP_INGRESS_ENABLED=${MCP_INGRESS_ENABLED:-1}

# Domains to exclude from Cloudflare IP whitelisting
if [ -z "${CLOUDFLARE_EXCLUDED_DOMAINS}" ]; then
  CLOUDFLARE_EXCLUDED_DOMAINS=()
fi

# Cloudflare IP ranges (IPv4 and IPv6)
# Source: https://www.cloudflare.com/ips/
if [ -z "${CLOUDFLARE_IPS}" ]; then
  CLOUDFLARE_IPS="103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,104.16.0.0/13,104.24.0.0/14,108.162.192.0/18,131.0.72.0/22,141.101.64.0/18,162.158.0.0/15,172.64.0.0/13,173.245.48.0/20,188.114.96.0/20,190.93.240.0/20,197.234.240.0/22,198.41.128.0/17,2400:cb00::/32,2606:4700::/32,2803:f800::/32,2405:b500::/32,2405:8100::/32,2a06:98c0::/29,2c0f:f248::/32"
fi

##
# Phase 1: Prepare per-domain data
#
# For every domain an associative array DOMAIN_DATA_<index> is created holding all
# the values an ingress template may need:
#   [BASE_DOMAIN]        hostname without path, e.g. "example.com" or "www.example.com"
#   [REDIRECT_DOMAIN]    counterpart hostname the domain redirects from (www/non-www)
#   [URL_PATH]           optional path for path-based domains, e.g. "en" for "example.com/en"
#   [TLS_SECRET_NAME]    TLS secret name, shared by all ingresses of the same hostname
#   [HTTP_AUTH_ENABLED]  1 when the domain is protected by HTTP basic auth
#   [WHITELIST_IPS]      IPs allowed to bypass HTTP basic auth
#   [CLOUDFLARE_ENABLED] 1 when the domain is routed through Cloudflare
#
# Ingress manifests rendered in phase 2 read the prepared data (via a nameref, see
# render_ingress) instead of copying configuration from an already generated ingress.
##

# Merge default and environment whitelist IPs: drop whitespace and normalize commas
# (duplicated, leading and trailing commas cover the empty-variable cases)
FINAL_WHITELIST_IPS=$(echo "${DEFAULT_WHITELIST_IPS},${WHITELIST_IPS}" | tr -d ' ' | sed 's/,\+/,/g;s/^,//;s/,$//')

# prepare_domain_data <domain-variable-name> <domain-index>
function prepare_domain_data() {
    local DOMAIN="${1}"
    local DOMAIN_INDEX="${2}"

    declare -g -A "DOMAIN_DATA_${DOMAIN_INDEX}"
    local -n DOMAIN_DATA="DOMAIN_DATA_${DOMAIN_INDEX}"

    local BASE_DOMAIN=${!DOMAIN}
    local URL_PATH=""

    if [[ "${BASE_DOMAIN}" == *"/"* ]]; then
        URL_PATH=${BASE_DOMAIN##*\/}
        BASE_DOMAIN=${BASE_DOMAIN%%\/*} # Remove path from Domain if exists
    fi

    DOMAIN_DATA[BASE_DOMAIN]="${BASE_DOMAIN}"
    DOMAIN_DATA[URL_PATH]="${URL_PATH}"

    if [[ ${BASE_DOMAIN} == "www."* ]]; then
        DOMAIN_DATA[REDIRECT_DOMAIN]=${BASE_DOMAIN#"www."}
    else
        DOMAIN_DATA[REDIRECT_DOMAIN]="www.${BASE_DOMAIN}"
    fi

    # Generate TLS secret name from BASE_DOMAIN to ensure domains with same host share the same certificate
    # Sanitize to meet Kubernetes naming requirements: lowercase alphanumeric and hyphens only, no leading/trailing hyphens
    DOMAIN_DATA[TLS_SECRET_NAME]="tls-$(echo "${BASE_DOMAIN}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/^-\+\|-\+$//g')"

    DOMAIN_DATA[HTTP_AUTH_ENABLED]=0
    if [ "${RUNNING_PRODUCTION}" -ne "1" ] || containsElement "${DOMAIN}" "${FORCE_HTTP_AUTH_IN_PRODUCTION[@]}"; then
        DOMAIN_DATA[HTTP_AUTH_ENABLED]=1
    fi

    DOMAIN_DATA[WHITELIST_IPS]="${FINAL_WHITELIST_IPS}"

    DOMAIN_DATA[CLOUDFLARE_ENABLED]=0
    if [ "${USING_CLOUDFLARE}" = "1" ] && ! containsElement "${DOMAIN}" "${CLOUDFLARE_EXCLUDED_DOMAINS[@]}"; then
        DOMAIN_DATA[CLOUDFLARE_ENABLED]=1
    fi

    yq e -i ".domains_urls[${DOMAIN_INDEX}].url=\"https://${BASE_DOMAIN}${URL_PATH:+/${URL_PATH}}\"" "${DOMAINS_URLS_FILEPATH}"
}

DOMAINS=(${DOMAINS[@]}) # Normalize to an array even when provided as a space-separated string
DOMAIN_COUNT=${#DOMAINS[@]}

for DOMAIN_INDEX in "${!DOMAINS[@]}"; do
    prepare_domain_data "${DOMAINS[${DOMAIN_INDEX}]}" "${DOMAIN_INDEX}"
done

##
# Phase 2: Render ingress manifests from templates
#
# render_ingress copies the given template, applies the data shared by all ingresses
# of the domain (name, hostname, TLS) and delegates template-specific behavior to the
# given configure function. To publish a new ingress with custom behavior, add
# a template to kubernetes/ingress/, write a configure function and call
# render_ingress below.
##

# render_ingress <template-filename> <target-filename> <ingress-name> <domain-index> [configure-function]
function render_ingress() {
    local TEMPLATE_FILENAME="${1}"
    local TARGET_FILENAME="${2}"
    local INGRESS_NAME="${3}"
    local DOMAIN_INDEX="${4}"
    local CONFIGURE_FUNCTION="${5:-}"
    local -n DOMAIN_DATA="DOMAIN_DATA_${DOMAIN_INDEX}"
    local TARGET_FILEPATH="${CONFIGURATION_TARGET_PATH}/ingress/${TARGET_FILENAME}"

    cp "${CONFIGURATION_TARGET_PATH}/ingress/${TEMPLATE_FILENAME}" "${TARGET_FILEPATH}"

    yq e -i "
      .metadata.name = \"${INGRESS_NAME}\" |
      .spec.rules[0].host = \"${DOMAIN_DATA[BASE_DOMAIN]}\" |
      .spec.tls[0].hosts += [\"${DOMAIN_DATA[BASE_DOMAIN]}\"] |
      .spec.tls[0].secretName = \"${DOMAIN_DATA[TLS_SECRET_NAME]}\"
    " "${TARGET_FILEPATH}"

    if [ -n "${CONFIGURE_FUNCTION}" ]; then
        ${CONFIGURE_FUNCTION} "${TARGET_FILEPATH}" "${DOMAIN_INDEX}"
    fi

    yq e -i ".resources += [\"../../ingress/${TARGET_FILENAME}\"]" "${CONFIGURATION_TARGET_PATH}/kustomize/webserver/kustomization.yaml"
}

# Main application ingress: serves the whole domain, redirects between the www and
# non-www variant and is protected by HTTP basic auth with IP whitelisting outside
# production (or when forced by FORCE_HTTP_AUTH_IN_PRODUCTION).
function configure_default_ingress() {
    local TARGET_FILEPATH="${1}"
    local DOMAIN_INDEX="${2}"
    local -n DOMAIN_DATA="DOMAIN_DATA_${DOMAIN_INDEX}"

    # Redirect http to https and redirect between the www and non-www variant of the domain
    local CONFIGURATION_SNIPPET='if ($scheme = http) { return 308 https://$host$request_uri; } '
    if [[ ${DOMAIN_DATA[BASE_DOMAIN]} == "www."* ]]; then
        CONFIGURATION_SNIPPET+='if ($host ~ ^(?!www\.)(?<domain>.+)$) { return 308 https://www.$domain$request_uri; }'
    else
        CONFIGURATION_SNIPPET+='if ($host ~ ^www\.(?<domain>.+)$) { return 308 https://$domain$request_uri; }'
    fi

    CONFIGURATION_SNIPPET="${CONFIGURATION_SNIPPET}" yq e -i '
      .metadata.annotations."nginx.ingress.kubernetes.io/configuration-snippet" = strenv(CONFIGURATION_SNIPPET)
    ' "${TARGET_FILEPATH}"

    yq e -i "
      .spec.rules += [{\"host\": \"${DOMAIN_DATA[REDIRECT_DOMAIN]}\"}] |
      .spec.tls[0].hosts += [\"${DOMAIN_DATA[REDIRECT_DOMAIN]}\"]
    " "${TARGET_FILEPATH}"

    if [ -n "${DOMAIN_DATA[URL_PATH]}" ]; then
        yq e -i ".spec.rules[0].http.paths[0].path = \"/${DOMAIN_DATA[URL_PATH]}\"" "${TARGET_FILEPATH}"
    fi

    if [ "${DOMAIN_DATA[HTTP_AUTH_ENABLED]}" = "1" ]; then
        yq e -i '
          .metadata.annotations."nginx.ingress.kubernetes.io/auth-type" = "basic" |
          .metadata.annotations."nginx.ingress.kubernetes.io/auth-secret" = "http-auth" |
          .metadata.annotations."nginx.ingress.kubernetes.io/auth-realm" = "Authentication Required - ok"
        ' "${TARGET_FILEPATH}"

        # Apply the whitelist allowing to bypass the HTTP basic auth if we have any IPs
        if [ -n "${DOMAIN_DATA[WHITELIST_IPS]}" ]; then
            WHITELIST_IPS="${DOMAIN_DATA[WHITELIST_IPS]}" yq e -i '
              .metadata.annotations."nginx.ingress.kubernetes.io/whitelist-source-range" = strenv(WHITELIST_IPS) |
              .metadata.annotations."nginx.ingress.kubernetes.io/satisfy" = "any"
            ' "${TARGET_FILEPATH}"
        fi
    fi

    if [ "${DOMAIN_DATA[CLOUDFLARE_ENABLED]}" = "1" ]; then
        yq e -i '.metadata.annotations."nginx.ingress.kubernetes.io/server-snippet" = "real_ip_header CF-Connecting-IP;"' "${TARGET_FILEPATH}"
    fi
}

for (( DOMAIN_INDEX=0; DOMAIN_INDEX<DOMAIN_COUNT; DOMAIN_INDEX++ )); do
    render_ingress ".ingress.yaml" "ingress-${DOMAIN_INDEX}.yaml" "eshop-domain-${DOMAIN_INDEX}" "${DOMAIN_INDEX}" configure_default_ingress
done

# MCP ingress: publishes the MCP paths (defined in the .ingress-mcp.yaml template)
# without HTTP basic auth so external MCP clients (e.g. Claude Code) stay reachable.
# Basic auth and the MCP Bearer token both use the single Authorization header, so
# while basic auth is enabled on the main ingress the Bearer token never reaches the
# application. The published paths are protected by the application itself (Bearer
# token on /_mcp) or are public by the OAuth specification.
#
# The MCP server is published only through the first domain, always on root-level
# paths (a path-based first domain does not shift them), and the ingress is rendered
# regardless of HTTP basic auth so the MCP paths are always served separately from
# the main ingress and the routing does not differ between environments.
#
# The ingress intentionally does not repeat any main ingress configuration:
# - the TLS certificate is reused via the shared TLS secret (no cert-manager
#   annotation, so no duplicate Certificate is issued),
# - server-scoped nginx settings of the main ingress (e.g. the Cloudflare
#   real_ip_header server-snippet) apply to the MCP locations automatically, because
#   ingress-nginx merges all ingresses of the same hostname into a single server block.
if [ "${MCP_INGRESS_ENABLED}" = "1" ]; then
    render_ingress ".ingress-mcp.yaml" "ingress-mcp.yaml" "eshop-mcp" 0
fi

echo -e "[${GREEN}OK${NO_COLOR}]"
