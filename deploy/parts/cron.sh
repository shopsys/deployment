#!/bin/bash -e

echo -n "Prepare Cron "

assertVariable "BASE_PATH"
assertVariable "CONFIGURATION_TARGET_PATH"

ITERATOR=0
for key in ${!CRON_INSTANCES[@]}; do

    CRONTAB_LINE="        ${CRON_INSTANCES[${key}]} . /root/.project_env.sh && cd /var/www/html/ && ./phing ${key} > /dev/null 2>&1"
    echo "${CRONTAB_LINE}" >> "${CONFIGURATION_TARGET_PATH}/configmap/cron-list.yaml"

    ITERATOR=$(expr $ITERATOR + 1)
done

echo "        " >> "${CONFIGURATION_TARGET_PATH}/configmap/cron-list.yaml"
unset CRON_INSTANCES

# Use FREEZE_TIMESTAMP for testing, otherwise use current timestamp
CRON_TIMESTAMP="${FREEZE_TIMESTAMP:-$(date +%s)}"
yq e -i ".spec.template.metadata.labels.date=\"${CRON_TIMESTAMP}\"" "${CONFIGURATION_TARGET_PATH}/deployments/cron.yaml"

echo -e "[${GREEN}OK${NO_COLOR}]"
