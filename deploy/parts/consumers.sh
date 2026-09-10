#!/bin/bash -e

# Generates consumer deployments and their Horizontal pod autoscalers from ${BASE_PATH}/deploy/consumers.yaml, see README.md, section "Consumers".
# Must be sourced before environment-variables.sh and kubernetes-variables.sh, which fill in the generated deployments

echo -n "Prepare Consumers "

assertVariable "BASE_PATH"
assertVariable "CONFIGURATION_TARGET_PATH"

if [ -z ${ENABLE_CONSUMER_AUTOSCALING} ]; then
    ENABLE_CONSUMER_AUTOSCALING=false
fi

CONSUMERS_YAML_PATH="${BASE_PATH}/deploy/consumers.yaml"

if [ ! -f "${CONSUMERS_YAML_PATH}" ]; then
    echo -e "[${YELLOW}SKIP${NO_COLOR}]"
    return
fi

# DEFAULT_CONSUMERS lives in the merge phase (another process), so the conflict is detected from the manifests it generated
if compgen -G "${CONFIGURATION_TARGET_PATH}/deployments/consumer-*.yaml" > /dev/null; then
    echo -e "[${RED}ERROR${NO_COLOR}] Consumers are declared both in DEFAULT_CONSUMERS (or orchestration/kubernetes/deployments) and deploy/consumers.yaml, use only one of them:"
    ls "${CONFIGURATION_TARGET_PATH}"/deployments/consumer-*.yaml
    exit 1
fi

# environment-variables.sh unsets the array after injecting it
if ! declare -p ENVIRONMENT_VARIABLES > /dev/null 2>&1; then
    echo -e "[${RED}ERROR${NO_COLOR}] consumers.sh must be sourced before environment-variables.sh in deploy-project.sh"
    exit 1
fi

if [ "$(yq e '(.consumers | tag) == "!!seq" and (.consumers | length) > 0' "${CONSUMERS_YAML_PATH}")" != true ]; then
    echo -e "[${RED}ERROR${NO_COLOR}] deploy/consumers.yaml must declare a non-empty list under the consumers key"
    exit 1
fi

# The deployment consumer-<name> labels its pods app=consumer-<name>, a label value of at most 63 characters.
# The regexes of the names also keep the field separators of the lines read by the loop below (semicolon and space) out of the values
INVALID_CONSUMER_NAMES=$(yq e '.consumers[] | (.name // "") | select(tostring | test("^[a-z0-9]([a-z0-9-]{0,52}[a-z0-9])?$") | not) | "Consumer name must match ^[a-z0-9]([a-z0-9-]{0,52}[a-z0-9])?$ (lowercase, starting and ending with a letter or digit, at most 54 characters), got '"'"'" + tostring + "'"'"'"' "${CONSUMERS_YAML_PATH}")

if [ -n "${INVALID_CONSUMER_NAMES}" ]; then
    echo -e "[${RED}ERROR${NO_COLOR}]"
    echo "${INVALID_CONSUMER_NAMES}"
    exit 1
fi

DUPLICATE_CONSUMER_NAMES=$(yq e '.consumers[].name' "${CONSUMERS_YAML_PATH}" | sort | uniq -d)

if [ -n "${DUPLICATE_CONSUMER_NAMES}" ]; then
    echo -e "[${RED}ERROR${NO_COLOR}] Consumer names must be unique, declared more than once:"
    echo "${DUPLICATE_CONSUMER_NAMES}"
    exit 1
fi

# Queue names become label selector values of the HPA metric, hence the Kubernetes label value rules
INVALID_NAMES=$(yq e '.consumers[] | (.name // "") as $consumer | ((.transports // []), (.autoscaling.queues // [])) | select(tag == "!!seq") | .[] | select(tag != "!!str" or (test("^[A-Za-z0-9]([A-Za-z0-9_.-]{0,61}[A-Za-z0-9])?$") | not)) | "Consumer '"'"'" + $consumer + "'"'"': transport or queue name must match ^[A-Za-z0-9]([A-Za-z0-9_.-]{0,61}[A-Za-z0-9])?$, got '"'"'" + tostring + "'"'"'"' "${CONSUMERS_YAML_PATH}")

if [ -n "${INVALID_NAMES}" ]; then
    echo -e "[${RED}ERROR${NO_COLOR}]"
    echo "${INVALID_NAMES}"
    exit 1
fi

# Every consumer is validated regardless of ENABLE_CONSUMER_AUTOSCALING, so that a broken declaration fails on every environment.
# yq quirks the rules rely on: the comma binds looser than the pipe (hence the parentheses around each group), a message not referring
# to the current node is emitted even when select() matched nothing, and traversing .autoscaling.* creates the missing key,
# so has("autoscaling") is evaluated first
CONSUMER_RULES=$(cat <<'YQ'
.consumers[] | (
    (select(((.transports | tag) != "!!seq") or ((.transports | length) == 0)) | "Consumer '" + ((.name // "") | tostring) + "': transports must be a non-empty list"),
    (select(((.replicas | tag) != "!!int") or (.replicas < 0)) | "Consumer '" + ((.name // "") | tostring) + "': replicas must be a non-negative integer, got '" + (.replicas | tostring) + "'"),
    (select(has("autoscaling") and ((.autoscaling | tag) != "!!map")) | "Consumer '" + ((.name // "") | tostring) + "': autoscaling must be a map with minReplicas, maxReplicas, threshold and optional queues, got '" + (.autoscaling | tostring) + "'"),
    (select(has("autoscaling") and ((.autoscaling | tag) == "!!map")) | (
        (select(((.autoscaling.minReplicas | tag) != "!!int") or (.autoscaling.minReplicas < 0)) | "Consumer '" + ((.name // "") | tostring) + "': autoscaling.minReplicas must be a non-negative integer (0 needs the HPAScaleToZero feature gate on the cluster), got '" + (.autoscaling.minReplicas | tostring) + "'"),
        (select((.autoscaling.maxReplicas | tag) != "!!int") | "Consumer '" + ((.name // "") | tostring) + "': autoscaling.maxReplicas must be an integer greater than autoscaling.minReplicas, got '" + (.autoscaling.maxReplicas | tostring) + "'"),
        (select(((.autoscaling.minReplicas | tag) == "!!int") and ((.autoscaling.maxReplicas | tag) == "!!int") and (.autoscaling.maxReplicas <= .autoscaling.minReplicas)) | "Consumer '" + ((.name // "") | tostring) + "': autoscaling.maxReplicas (" + (.autoscaling.maxReplicas | tostring) + ") must be greater than autoscaling.minReplicas (" + (.autoscaling.minReplicas | tostring) + ")"),
        (select(((.autoscaling.threshold | tag) != "!!int") or (.autoscaling.threshold < 1)) | "Consumer '" + ((.name // "") | tostring) + "': autoscaling.threshold must be a positive integer of ready messages per pod, got '" + (.autoscaling.threshold | tostring) + "'"),
        (select((.autoscaling | has("queues")) and (((.autoscaling.queues | tag) != "!!seq") or ((.autoscaling.queues | length) == 0))) | "Consumer '" + ((.name // "") | tostring) + "': autoscaling.queues must be a non-empty list (or omitted to use transports)")
    ))
)
YQ
)
INVALID_FIELDS=$(yq e "${CONSUMER_RULES}" "${CONSUMERS_YAML_PATH}")

if [ -n "${INVALID_FIELDS}" ]; then
    echo -e "[${RED}ERROR${NO_COLOR}]"
    echo "${INVALID_FIELDS}"
    exit 1
fi

CONSUMERS_LINES=$(yq e '.consumers[] | [(has("autoscaling") | tostring), .name, (.transports | join(" ")), .replicas, (.autoscaling.minReplicas // ""), (.autoscaling.maxReplicas // ""), (.autoscaling.threshold // ""), ((.autoscaling.queues // .transports) | join(" "))] | join(";")' "${CONSUMERS_YAML_PATH}")

while IFS=";" read -r HAS_AUTOSCALING NAME TRANSPORT_NAMES REPLICAS_COUNT MIN_REPLICAS MAX_REPLICAS SCALE_THRESHOLD QUEUE_NAMES; do
    create_consumer_deployment_manifest "${NAME}" "${TRANSPORT_NAMES}" "${REPLICAS_COUNT}"

    if [ "${HAS_AUTOSCALING}" = true ] && [ "${ENABLE_CONSUMER_AUTOSCALING}" = true ]; then
        # The autoscaler owns the replicas count, a static count in the deployment would reset it on every deploy
        yq e -i 'del(.spec.replicas)' "${CONFIGURATION_TARGET_PATH}/deployments/consumer-${NAME}.yaml"

        create_consumer_hpa_manifest "${NAME}" "${MIN_REPLICAS}" "${MAX_REPLICAS}" "${SCALE_THRESHOLD}" "${QUEUE_NAMES}"
    fi
done <<< "${CONSUMERS_LINES}"

unset CONSUMERS_YAML_PATH INVALID_CONSUMER_NAMES DUPLICATE_CONSUMER_NAMES INVALID_NAMES CONSUMER_RULES INVALID_FIELDS CONSUMERS_LINES HAS_AUTOSCALING NAME TRANSPORT_NAMES REPLICAS_COUNT MIN_REPLICAS MAX_REPLICAS SCALE_THRESHOLD QUEUE_NAMES

echo -e "[${GREEN}OK${NO_COLOR}]"
