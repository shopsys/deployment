#!/bin/bash -e

echo -n "Prepare RabbitMQ management domain "

assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "DOMAIN_HOSTNAME_1"

if [ -z "${RABBITMQ_DOMAIN_HOSTNAME}" ]; then
    RABBITMQ_DOMAIN_HOSTNAME="rabbitmq.${DOMAIN_HOSTNAME_1}"
fi

yq e -i ".spec.rules[0].host=\"${RABBITMQ_DOMAIN_HOSTNAME}\"" "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml"
yq e -i ".spec.tls[0].hosts[0] = \"${RABBITMQ_DOMAIN_HOSTNAME}\"" "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml"

if [ -n "${RABBITMQ_IP_WHITELIST}" ]; then
    yq e -i ".metadata.annotations.\"nginx.ingress.kubernetes.io/whitelist-source-range\"=\"${RABBITMQ_IP_WHITELIST}\"" "${CONFIGURATION_TARGET_PATH}/ingress/ingress-rabbitmq.yaml"
fi

echo -e "[${GREEN}OK${NO_COLOR}]"
