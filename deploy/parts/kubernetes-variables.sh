#!/bin/bash -e

echo -n "Prepare Kubernetes variables "

assertVariable "RUNNING_PRODUCTION"
assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "S3_ENDPOINT"
assertVariable "PROJECT_NAME"

if [ -z ${REDIS_VERSION} ]; then
  REDIS_VERSION='redis:7.4-alpine'
fi

VARS+=(REDIS_VERSION)

if [[ $PROJECT_NAME != *"-"* ]]; then
    echo -e "[${RED}ERROR${NO_COLOR}] PROJECT_NAME must contain a dash to separate project and environment"
    exit 1
fi

projectNameSplit=(${PROJECT_NAME//-/ })
NAME_OF_PROJECT=${projectNameSplit[0]}
PROJECT_ENVIRONMENT=${projectNameSplit[1]}

VARS+=(NAME_OF_PROJECT)
VARS+=(PROJECT_ENVIRONMENT)

DOMAINS_URLS_FILEPATH="$(find_file "config" "domains_urls")"

VARS+=(DOMAINS_URLS_FILEPATH)

CONFIG_PREFIX="config/"
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
