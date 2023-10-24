#!/bin/bash -e

echo -n "Prepare RabbitMQ management domain "

assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "DOMAIN_HOSTNAME_1"

DOMAIN="rabbitmq.${DOMAIN_HOSTNAME_1}"

yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml" spec.rules[0].host ${DOMAIN}
yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml" spec.tls[0].hosts[+] ${DOMAIN}

if [ -n "${RABBITMQ_IP_WHITELIST}" ]; then
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml" metadata.annotations."\"nginx.ingress.kubernetes.io/whitelist-source-range\"" "${RABBITMQ_IP_WHITELIST}"
fi

echo -e "[${GREEN}OK${NO_COLOR}]"
