#!/bin/bash -e

echo -n "Prepare Kubernetes variables "

assertVariable "RUNNING_PRODUCTION"
assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "S3_ENDPOINT"

if [ -z ${REDIS_VERSION} ]; then
  REDIS_VERSION='redis:7.0-alpine'
fi

VARS+=(REDIS_VERSION)

DOMAINS_URLS_FILEPATH="$(find_file "$(get_config_directory)" "domains_urls")"

VARS+=(DOMAINS_URLS_FILEPATH)

CONFIG_PREFIX="$(get_config_directory)/"
DOMAINS_URLS_FILENAME=${DOMAINS_URLS_FILEPATH#"$CONFIG_PREFIX"}

VARS+=(DOMAINS_URLS_FILENAME)

VARS+=(S3_ENDPOINT)

FILES=$( find $CONFIGURATION_TARGET_PATH -type f )
for FILE in $FILES; do
    for VAR in ${VARS[@]}; do
        assertVariable $VAR
        sed -i "s|{{$VAR}}|${!VAR}|g" "$FILE"
    done
done
unset FILES
unset VARS

echo -e "[${GREEN}OK${NO_COLOR}]"
