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

# Domains to exclude from Cloudflare IP whitelisting
if [ -z "${CLOUDFLARE_EXCLUDED_DOMAINS}" ]; then
  CLOUDFLARE_EXCLUDED_DOMAINS=()
fi

# Cloudflare IP ranges (IPv4 and IPv6)
# Source: https://www.cloudflare.com/ips/
if [ -z "${CLOUDFLARE_IPS}" ]; then
  CLOUDFLARE_IPS="103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,104.16.0.0/13,104.24.0.0/14,108.162.192.0/18,131.0.72.0/22,141.101.64.0/18,162.158.0.0/15,172.64.0.0/13,173.245.48.0/20,188.114.96.0/20,190.93.240.0/20,197.234.240.0/22,198.41.128.0/17,2400:cb00::/32,2606:4700::/32,2803:f800::/32,2405:b500::/32,2405:8100::/32,2a06:98c0::/29,2c0f:f248::/32"
fi

# Configure domains
DOMAIN_ITERATOR=0

for DOMAIN in ${DOMAINS[@]}; do
    INGRESS_FILENAME="ingress-${DOMAIN_ITERATOR}.yaml"

    cp "${CONFIGURATION_TARGET_PATH}/ingress/.ingress.yaml" "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}"

    BASENAME=${!DOMAIN}
    DOMAIN_PATH=""

    if [[ "${BASENAME}" == *"/"* ]]; then
        DOMAIN_PATH=${BASENAME##*\/}
        BASENAME=${BASENAME%%\/*} # Remove path from Domain if exists
    fi

    if [[ ${BASENAME} == "www."* ]]; then
        BASE_DOMAIN=${BASENAME}
        REDIRECT_DOMAIN=${BASENAME#"www."}

        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/configuration-snippet\"" 'if ($scheme = http) { return 308 https://$host$request_uri; } if ($host ~ ^(?!www\.)(?<domain>.+)$) { return 308 https://www.$domain$request_uri; }'
    else
        BASE_DOMAIN=${BASENAME}
        REDIRECT_DOMAIN="www.${BASENAME}"

        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/configuration-snippet\"" 'if ($scheme = http) { return 308 https://$host$request_uri; } if ($host ~ ^www\.(?<domain>.+)$) { return 308 https://$domain$request_uri; }'
    fi

    if [ ! -z "${DOMAIN_PATH}" ]; then
        yq write --inplace ${DOMAINS_URLS_FILEPATH} domains_urls[${DOMAIN_ITERATOR}].url https://${BASE_DOMAIN}/${DOMAIN_PATH}
    else
        yq write --inplace ${DOMAINS_URLS_FILEPATH} domains_urls[${DOMAIN_ITERATOR}].url https://${BASE_DOMAIN}
    fi

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.name "eshop-domain-${DOMAIN_ITERATOR}"
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" spec.tls[0].secretName "tls-eshop-domain-${DOMAIN_ITERATOR}"

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" spec.rules[0].host ${BASE_DOMAIN}
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" spec.tls[0].hosts[+] ${BASE_DOMAIN}

    if [ ! -z "${DOMAIN_PATH}" ]; then
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" spec.rules[0].http.paths[0].path "/${DOMAIN_PATH}/"
    fi

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" spec.rules[+].host ${REDIRECT_DOMAIN}
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" spec.tls[0].hosts[+] ${REDIRECT_DOMAIN}

    # When domain is not in production we need to whitelist our IPs. But this also enables access outside Cloudflare
    if [ ${RUNNING_PRODUCTION} -ne "1" ] || containsElement ${DOMAIN} ${FORCE_HTTP_AUTH_IN_PRODUCTION[@]}; then
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/auth-type\"" basic
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/auth-secret\"" http-auth
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/auth-realm\"" "Authentication Required - ok"

        if [ -n "${WHITELIST_IPS}" ]; then
            FINAL_WHITELIST_IPS="${WHITELIST_IPS}"
        fi
    else
        # If domain is running in production all rules should be configured in Cloudflare so we whitelist only CF IPs
        if [ "${USING_CLOUDFLARE}" = "1" ] && ! containsElement ${DOMAIN} ${CLOUDFLARE_EXCLUDED_DOMAINS[@]}; then
            FINAL_WHITELIST_IPS="${CLOUDFLARE_IPS}"
        fi
    fi

    # Apply the final whitelist if we have any IPs
    if [ -n "${FINAL_WHITELIST_IPS}" ]; then
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/whitelist-source-range\"" "${FINAL_WHITELIST_IPS}"
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/satisfy\"" "any"
    fi

    if [ "${USING_CLOUDFLARE}" = "1" ] && ! containsElement ${DOMAIN} ${CLOUDFLARE_EXCLUDED_DOMAINS[@]}; then
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/server-snippet\"" "real_ip_header CF-Connecting-IP;"
    fi

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/kustomize/webserver/kustomization.yaml" resources[+] "../../ingress/${INGRESS_FILENAME}"

    DOMAIN_ITERATOR=$(expr $DOMAIN_ITERATOR + 1)
done

echo -e "[${GREEN}OK${NO_COLOR}]"
