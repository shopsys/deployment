#!/bin/bash -e

# Generates Prometheus Probe manifests for TTFB measurement via blackbox exporter.
# See README for configuration format.

assertVariable "PROJECT_ENVIRONMENT"
assertVariable "NAME_OF_PROJECT"
assertVariable "CONFIGURATION_TARGET_PATH"
assertVariable "RUNNING_PRODUCTION"

if [ "${PROJECT_ENVIRONMENT}" != "prod" ]; then
    return 0
fi

# Silent skip if TTFB_PROBES is not defined at all (project doesn't use probes).
if ! declare -p TTFB_PROBES >/dev/null 2>&1; then
    return 0
fi

if [ ${#TTFB_PROBES[@]} -eq 0 ]; then
    return 0
fi

echo "Prepare TTFB probes"

PROBE_TEMPLATE_PATH="${CONFIGURATION_TARGET_PATH}/manifest-templates/probe.template.yaml"
PROBES_DIR="${CONFIGURATION_TARGET_PATH}/probes"
PROBES_KUSTOMIZATION="${CONFIGURATION_TARGET_PATH}/kustomize/webserver/kustomization.yaml"

if [ ! -f "${PROBE_TEMPLATE_PATH}" ]; then
    echo -e "    [${YELLOW}WARN${NO_COLOR}] probe template ${PROBE_TEMPLATE_PATH} not found - skipping all TTFB probes"
    return 0
fi

mkdir -p "${PROBES_DIR}"

if [ -z "${FORCE_HTTP_AUTH_IN_PRODUCTION}" ]; then
    FORCE_HTTP_AUTH_IN_PRODUCTION=()
fi

TTFB_PROBES_DOMAIN=${TTFB_PROBES_DOMAIN:-DOMAIN_HOSTNAME_1}
DOMAIN=${!TTFB_PROBES_DOMAIN}

if [ -z "${DOMAIN}" ]; then
    echo -e "    [${YELLOW}WARN${NO_COLOR}] domain variable ${TTFB_PROBES_DOMAIN} is not set - skipping all TTFB probes"
    return 0
fi

# HTTP auth — same rules as domains.sh:84. Applied once, because all probes
# target the same domain. Embed user:password@ before the hostname whenever:
#   - RUNNING_PRODUCTION != 1 (whole site is behind auth), or
#   - the domain is listed in FORCE_HTTP_AUTH_IN_PRODUCTION.
AUTH_PREFIX=""
if [ "${RUNNING_PRODUCTION}" != "1" ] || containsElement "${TTFB_PROBES_DOMAIN}" "${FORCE_HTTP_AUTH_IN_PRODUCTION[@]}"; then
    if [ -z "${HTTP_AUTH_CREDENTIALS}" ]; then
        echo -e "    [${YELLOW}WARN${NO_COLOR}] HTTP auth is active for ${TTFB_PROBES_DOMAIN} but HTTP_AUTH_CREDENTIALS is not set - skipping all TTFB probes"
        return 0
    fi
    AUTH_PREFIX="${HTTP_AUTH_CREDENTIALS}@"
fi

# Sort keys for deterministic output (associative array iteration order is
# implementation-defined and would make snapshots and logs non-reproducible).
readarray -t SORTED_PROBE_TYPES < <(printf '%s\n' "${!TTFB_PROBES[@]}" | sort)

for PROBE_TYPE in "${SORTED_PROBE_TYPES[@]}"; do
    PROBE_PATH="${TTFB_PROBES[${PROBE_TYPE}]}"

    # Probe type must be a single alphanumeric word — keeps resource names
    # predictable and avoids slug collisions (e.g. "Home Page" vs "home-page").
    if [[ ! "${PROBE_TYPE}" =~ ^[a-zA-Z0-9]+$ ]]; then
        echo -e "    [${YELLOW}WARN${NO_COLOR}] invalid probe type \"${PROBE_TYPE}\" (only letters and digits are allowed, no spaces or hyphens) - skipped"
        continue
    fi

    # Normalize path: accept "", "/", "/foo", "foo", "foo/bar" and produce
    # either "" or "/foo..." — never a bare "/" and never missing leading /.
    PROBE_PATH="${PROBE_PATH#/}"
    [ -n "${PROBE_PATH}" ] && PROBE_PATH="/${PROBE_PATH}"

    PROBE_SLUG=$(echo "${PROBE_TYPE}" | tr '[:upper:]' '[:lower:]')
    PROBE_URL="https://${AUTH_PREFIX}${DOMAIN}${PROBE_PATH}"
    PROBE_FILENAME="probe-${PROBE_SLUG}.yaml"
    PROBE_FILE="${PROBES_DIR}/${PROBE_FILENAME}"

    cp "${PROBE_TEMPLATE_PATH}" "${PROBE_FILE}"

    PROBE_NAME="ttfb-${PROBE_SLUG}" \
    PROBE_URL="${PROBE_URL}" \
    PROBE_PROJECT="${NAME_OF_PROJECT}" \
    PROBE_TYPE_LABEL="${PROBE_TYPE}" \
    yq e -i '
        .metadata.name = strenv(PROBE_NAME) |
        .spec.targets.staticConfig.static[0] = strenv(PROBE_URL) |
        .spec.targets.staticConfig.labels.project = strenv(PROBE_PROJECT) |
        .spec.targets.staticConfig.labels.type = strenv(PROBE_TYPE_LABEL)
    ' "${PROBE_FILE}"

    yq e -i ".resources += [\"../../probes/${PROBE_FILENAME}\"]" "${PROBES_KUSTOMIZATION}"

    echo -e "    [${GREEN}OK${NO_COLOR}] ttfb-${PROBE_SLUG} (${PROBE_TYPE}): ${DOMAIN}${PROBE_PATH}"
done
