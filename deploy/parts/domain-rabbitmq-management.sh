#!/bin/bash -e

echo -n "Prepare RabbitMQ management domain "

assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "DOMAIN_HOSTNAME_1"

if [ -z "${RABBITMQ_DOMAIN_HOSTNAME}" ]; then
    RABBITMQ_DOMAIN_HOSTNAME="rabbitmq.${DOMAIN_HOSTNAME_1}"
fi

yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml" spec.rules[0].host ${RABBITMQ_DOMAIN_HOSTNAME}
yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml" spec.tls[0].hosts[+] ${RABBITMQ_DOMAIN_HOSTNAME}

if [ -n "${RABBITMQ_IP_WHITELIST}" ]; then
    yq write --inplace "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml" metadata.annotations."\"nginx.ingress.kubernetes.io/whitelist-source-range\"" "${RABBITMQ_IP_WHITELIST}"
fi

echo -e "[${GREEN}OK${NO_COLOR}]"
