#!/bin/bash -e

echo -n "Prepare Domains "

assertVariable "BASE_PATH"
assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "DOMAINS"
assertVariable "RUNNING_PRODUCTION"

DOMAINS_URLS_DIST_FILEPATH="$(find_file "${BASE_PATH}/config" "domains_urls" 1)"
DOMAINS_URLS_FILEPATH="$(remove_dist "${DOMAINS_URLS_DIST_FILEPATH}")"

cp ${DOMAINS_URLS_DIST_FILEPATH} ${DOMAINS_URLS_FILEPATH}

if [ -z ${FORCE_HTTP_AUTH_IN_PRODUCTION} ]; then
  FORCE_HTTP_AUTH_IN_PRODUCTION=()
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

    if [ ${RUNNING_PRODUCTION} -ne "1" ] || containsElement ${DOMAIN} ${FORCE_HTTP_AUTH_IN_PRODUCTION[@]}; then
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/auth-type\"" basic
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/auth-secret\"" http-auth
        yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/auth-realm\"" "Authentication Required - ok"

        if [ -n "${WHITELIST_IPS}" ]; then
            yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/satisfy\"" "any"
            yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/${INGRESS_FILENAME}" metadata.annotations."\"nginx.ingress.kubernetes.io/whitelist-source-range\"" "${WHITELIST_IPS}"
        fi
    fi

    yq write --inplace "${CONFIGURATION_TARGET_PATH}/kustomize/webserver/kustomization.yaml" resources[+] "../../ingress/${INGRESS_FILENAME}"

    DOMAIN_ITERATOR=$(expr $DOMAIN_ITERATOR + 1)
done

echo -e "[${GREEN}OK${NO_COLOR}]"
