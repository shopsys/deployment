#!/bin/bash
set -e

# Deployment Manifest Test Runner
# ================================
# This script runs test scenarios to verify Kubernetes manifest generation.
#
# Usage:
#   ./run-tests.sh                    # Run all scenarios
#   ./run-tests.sh scenario-name      # Run specific scenario
#   ./run-tests.sh deploy             # Run only the deploy tests (deploy.sh with mocked kubectl)
#   ./run-tests.sh --list             # List available scenarios
#   ./run-tests.sh --update           # Update expected files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/lib/test-helpers.sh"

# Configuration
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"
TMP_DIR="${SCRIPT_DIR}/tmp"

# Options (can also be set via environment variables for backwards compatibility)
UPDATE_MODE="${UPDATE:-0}"
KEEP_TMP="${KEEP_TMP:-0}"
LIST_ONLY=0
SPECIFIC_SCENARIO=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --list|-l)
            LIST_ONLY=1
            shift
            ;;
        --update|-u)
            UPDATE_MODE=1
            shift
            ;;
        --keep-tmp|-k)
            KEEP_TMP=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [scenario-name]"
            echo ""
            echo "Options:"
            echo "  --list, -l      List available scenarios"
            echo "  --update, -u    Update expected files with generated output"
            echo "  --keep-tmp, -k  Keep temporary files after tests"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                          # Run all tests"
            echo "  $0 basic-production         # Run specific scenario"
            echo "  $0 deploy                   # Run only the deploy tests (deploy.sh with mocked kubectl)"
            echo "  $0 --update                 # Update all expected files"
            echo "  $0 --update basic-production  # Update specific scenario"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            SPECIFIC_SCENARIO="$1"
            shift
            ;;
    esac
done

# Export for helper functions
export KEEP_TMP

# List scenarios if requested
if [ $LIST_ONLY -eq 1 ]; then
    echo "Available test scenarios:"
    echo ""
    for scenario_dir in "${SCENARIOS_DIR}"/*/; do
        if [ -d "$scenario_dir" ]; then
            scenario_name=$(basename "$scenario_dir")
            description=""
            if [ -f "${scenario_dir}/description.txt" ]; then
                description=" - $(cat "${scenario_dir}/description.txt")"
            fi
            echo "  ${scenario_name}${description}"
        fi
    done
    echo "  deploy - deploy.sh of the scenarios above with mocked kubectl (the migrate-application step and the consumer autoscaler cleanup)"
    exit 0
fi

# Check for required tools
check_requirements() {
    local missing=0

    if ! command -v yq &> /dev/null; then
        print_error "yq is required but not installed"
        missing=1
    fi

    if ! command -v kustomize &> /dev/null; then
        print_error "kustomize is required but not installed"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

# Set up a test environment for a scenario
setup_test_environment() {
    local scenario_name="$1"
    local domain_count="$2"
    local test_tmp="${TMP_DIR}/${scenario_name}"

    # Clean up previous run
    rm -rf "$test_tmp"
    mkdir -p "$test_tmp"

    # Create project structure that mimics a real project
    mkdir -p "${test_tmp}/vendor/shopsys/deployment"
    mkdir -p "${test_tmp}/orchestration"
    mkdir -p "${test_tmp}/config"
    mkdir -p "${test_tmp}/var/deployment"
    mkdir -p "${test_tmp}/deploy"

    # Link the actual kubernetes manifests and deploy scripts
    ln -s "${PROJECT_ROOT}/kubernetes" "${test_tmp}/vendor/shopsys/deployment/kubernetes"
    ln -s "${PROJECT_ROOT}/deploy" "${test_tmp}/vendor/shopsys/deployment/deploy"

    # Provide required project-level overrides that are no longer shipped by deployment package.
    local fixtures_orchestration_path="${PROJECT_ROOT}/tests/fixtures/orchestration"
    if [ -d "${fixtures_orchestration_path}" ]; then
        cp -R "${fixtures_orchestration_path}/." "${test_tmp}/orchestration/"
    fi

    # Create domains_urls.yaml.dist dynamically based on domain count
    echo "domains_urls:" > "${test_tmp}/config/domains_urls.yaml.dist"
    for i in $(seq 1 ${domain_count}); do
        echo "    -   id: ${i}" >> "${test_tmp}/config/domains_urls.yaml.dist"
        echo "        url: ~" >> "${test_tmp}/config/domains_urls.yaml.dist"
    done

    # Create basicHttpAuth file (required by deploy.sh)
    mkdir -p "${test_tmp}/deploy"
    echo "testuser:\$apr1\$test\$hashedpassword" > "${test_tmp}/deploy/basicHttpAuth"

    # Provide project-level consumer declaration (read by deploy/parts/consumers.sh) when the scenario ships one
    if [ -f "${SCENARIOS_DIR}/${scenario_name}/consumers.yaml" ]; then
        cp "${SCENARIOS_DIR}/${scenario_name}/consumers.yaml" "${test_tmp}/deploy/consumers.yaml"
    fi

    echo "$test_tmp"
}

# Build one kustomization into the output file, fail (with the kustomize error on stderr) when the build fails
build_output() {
    local kustomize_path="$1"
    local output_file="$2"

    if ! build_kustomize "$kustomize_path" "$output_file"; then
        print_error "kustomize build failed for $(basename "$output_file"):" >&2
        head -n 5 "$output_file" >&2
        return 1
    fi
}

# Build kustomize outputs
build_outputs() {
    local test_tmp="$1"
    local output_dir="${test_tmp}/output"

    mkdir -p "$output_dir"

    local config_path="${test_tmp}/var/deployment/kubernetes"

    # Build webserver kustomize output
    if [ -d "${config_path}/kustomize/webserver" ]; then
        build_output "${config_path}/kustomize/webserver" "${output_dir}/webserver.yaml" || return 1
    fi

    # Build migrate-application outputs for each type
    for deploy_type in continuous-deploy first-deploy first-deploy-with-demo-data; do
        if [ -d "${config_path}/kustomize/migrate-application/${deploy_type}" ]; then
            build_output "${config_path}/kustomize/migrate-application/${deploy_type}" \
                "${output_dir}/migrate-${deploy_type}.yaml" || return 1
        fi
    done

    # Build cron kustomize output
    if [ -d "${config_path}/kustomize/cron" ]; then
        build_output "${config_path}/kustomize/cron" "${output_dir}/cron.yaml" || return 1
    fi

    # Copy individual files that aren't built by kustomize
    cp "${config_path}/horizontalPodAutoscaler.yaml" "${output_dir}/" 2>/dev/null || true
    cp "${config_path}/horizontalStorefrontAutoscaler.yaml" "${output_dir}/" 2>/dev/null || true
    cp "${config_path}/namespace.yaml" "${output_dir}/" 2>/dev/null || true

    echo "$output_dir"
}

# Run the given phases of the scenario's deploy-project.sh, each in its own process
run_scenario_phases() {
    local scenario_dir="$1"
    local test_tmp="$2"
    shift 2

    (
        # Source default environment variables
        source "${SCRIPT_DIR}/lib/default-env.sh"

        # Source scenario-specific overrides if exists
        if [ -f "${scenario_dir}/env.sh" ]; then
            source "${scenario_dir}/env.sh"
        fi

        # Export BASE_PATH for deploy-project.sh
        export BASE_PATH="${test_tmp}"
        export CONFIGURATION_TARGET_PATH="${BASE_PATH}/var/deployment/kubernetes"
        export DEPLOY_TARGET_PATH="${BASE_PATH}/var/deployment/deploy"
        export BASIC_AUTH_PATH="${BASE_PATH}/deploy/basicHttpAuth"

        # Freeze timestamp for deterministic test output
        export FREEZE_TIMESTAMP="1234567890"

        # Change to BASE_PATH - required for relative paths in kubernetes-variables.sh
        cd "${BASE_PATH}"

        # One process per phase as in a real project, where "merge" runs in the image build and "deploy" in the CI job,
        # so nothing defined by the merge phase (e.g. DEFAULT_CONSUMERS) leaks into the following phase.
        # bash -e: the -e of the shebang is ignored by "bash script"
        local phase
        for phase in "$@"; do
            bash -e "${scenario_dir}/deploy-project.sh" "$phase" || exit $?
        done
    )
}

# Run the merge and the generate phase of the scenario's deploy-project.sh
run_deploy_project() {
    run_scenario_phases "$1" "$2" merge generate
}

# Run a single test scenario
run_scenario() {
    local scenario_name="$1"
    local scenario_dir="${SCENARIOS_DIR}/${scenario_name}"

    print_scenario_header "$scenario_name"

    # Validate scenario exists
    if [ ! -d "$scenario_dir" ]; then
        print_error "Scenario not found: $scenario_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    if [ ! -f "${scenario_dir}/deploy-project.sh" ]; then
        print_error "Missing deploy-project.sh in scenario: $scenario_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    # Get domain count from env.sh
    local domain_count=1
    if [ -f "${scenario_dir}/env.sh" ]; then
        domain_count=$(source "${scenario_dir}/env.sh" && echo "${DOMAIN_COUNT:-1}")
    fi

    # Set up test environment
    print_info "Setting up test environment..."
    local test_tmp
    test_tmp=$(setup_test_environment "$scenario_name" "$domain_count")

    # Generate manifests using scenario's deploy-project.sh
    print_info "Generating manifests using deploy-project.sh..."

    # A scenario with expected-error.txt must fail during the generation with every line of the file in its output
    if [ -f "${scenario_dir}/expected-error.txt" ]; then
        local expected_error generation_output

        if generation_output=$(run_deploy_project "$scenario_dir" "$test_tmp" 2>&1); then
            print_error "${scenario_name}: generation succeeded, expected failure with: $(head -n 1 "${scenario_dir}/expected-error.txt")"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            while IFS= read -r expected_error || [ -n "$expected_error" ]; do
                if echo "$generation_output" | grep -qF -- "$expected_error"; then
                    print_success "${scenario_name}: generation failed with: ${expected_error}"
                    TESTS_PASSED=$((TESTS_PASSED + 1))
                else
                    print_error "${scenario_name}: generation failed, but without the expected text: ${expected_error}"
                    echo ""
                    echo "$generation_output" | tail -n 20
                    echo ""
                    TESTS_FAILED=$((TESTS_FAILED + 1))
                fi
            done < "${scenario_dir}/expected-error.txt"
        fi

        cleanup_test_env "$test_tmp"
        return 0
    fi

    run_deploy_project "$scenario_dir" "$test_tmp" || {
        print_error "Manifest generation failed for scenario: $scenario_name (expected files not updated)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        cleanup_test_env "$test_tmp"
        return 1
    }

    # Build kustomize outputs
    print_info "Building kustomize outputs..."
    local output_dir
    if ! output_dir=$(build_outputs "$test_tmp"); then
        print_error "Kustomize build failed for scenario: $scenario_name (expected files not updated)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        cleanup_test_env "$test_tmp"
        return 1
    fi

    # Invariants independent of the expected files, so that a wrong output cannot be recorded as expected by --update
    print_info "Checking manifest invariants..."
    if ! check_consumer_invariants "$scenario_name" "$output_dir" "$test_tmp"; then
        print_error "Manifest invariants violated for scenario: $scenario_name (expected files not updated)"
        cleanup_test_env "$test_tmp"
        return 1
    fi

    # Update mode: copy generated to expected
    if [ "${UPDATE_MODE}" = "1" ]; then
        print_info "Updating expected files..."
        rm -rf "${scenario_dir}/expected"
        mkdir -p "${scenario_dir}/expected"
        cp -R "${output_dir}/." "${scenario_dir}/expected/"
        print_success "Expected files updated for scenario: $scenario_name"
        return 0
    fi

    # Compare outputs
    print_info "Comparing outputs..."
    local expected_dir="${scenario_dir}/expected"

    if [ ! -d "$expected_dir" ]; then
        print_warning "No expected directory found. Run with --update to create."
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        cleanup_test_env "$test_tmp"
        return 2
    fi

    compare_directories "$expected_dir" "$output_dir" "${scenario_name}: "

    # Cleanup
    cleanup_test_env "$test_tmp"
}

# ---------------------------------------------------------------------------------------------------------------------
# Deploy tests: run the deploy phase (deploy/parts/deploy.sh) of a scenario with the mocked kubectl and sleep from tests/lib/mock
# and check the kubectl calls of the migrate-application step, see "Deploy tests" in tests/README.md
# ---------------------------------------------------------------------------------------------------------------------

# Runs the merge phase of a scenario, then the deploy phase with the mocked kubectl. Hooks (function names, optional) run
# before the merge phase (e.g. to override a template in orchestration) and between the phases (e.g. to break a kustomization).
# Results: DEPLOY_EXIT_CODE, DEPLOY_OUTPUT, DEPLOY_KUBECTL_CALLS (one kubectl invocation per line) and DEPLOY_TEST_TMP
run_mocked_deploy() {
    local scenario_name="$1"
    local deployed_hpas="$2"
    local before_merge_hook="${3:-}"
    local after_merge_hook="${4:-}"
    local scenario_dir="${SCENARIOS_DIR}/${scenario_name}"

    local domain_count=1
    if [ -f "${scenario_dir}/env.sh" ]; then
        domain_count=$(source "${scenario_dir}/env.sh" && echo "${DOMAIN_COUNT:-1}")
    fi
    DEPLOY_TEST_TMP=$(setup_test_environment "$scenario_name" "$domain_count")

    local kubectl_log="${DEPLOY_TEST_TMP}/kubectl.log"
    : > "$kubectl_log"

    if [ -n "$before_merge_hook" ]; then
        "$before_merge_hook" "$DEPLOY_TEST_TMP"
    fi

    DEPLOY_EXIT_CODE=0
    DEPLOY_KUBECTL_CALLS=""
    DEPLOY_OUTPUT=$(run_scenario_phases "$scenario_dir" "$DEPLOY_TEST_TMP" merge 2>&1) || DEPLOY_EXIT_CODE=$?
    if [ "$DEPLOY_EXIT_CODE" -ne 0 ]; then
        return
    fi

    if [ -n "$after_merge_hook" ]; then
        "$after_merge_hook" "$DEPLOY_TEST_TMP"
    fi

    DEPLOY_OUTPUT=$(
        export PATH="${SCRIPT_DIR}/lib/mock:${PATH}"
        export KUBECTL_LOG="$kubectl_log"
        export MOCK_DEPLOYED_HPAS="$deployed_hpas"
        export DISABLE_WEBSITE_RUNNING_CHECK=true
        run_scenario_phases "$scenario_dir" "$DEPLOY_TEST_TMP" deploy 2>&1
    ) || DEPLOY_EXIT_CODE=$?
    DEPLOY_KUBECTL_CALLS=$(cat "$kubectl_log")
}

# assert_deploy "<description>" <command...>: the command decides the result
assert_deploy() {
    local description="$1"
    shift

    if "$@"; then
        print_success "deploy: ${description}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "deploy: ${description}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        DEPLOY_CASE_FAILED=1
    fi
}

# 1-based line of the first kubectl call matching the pattern (fixed string), empty when none
kubectl_call_line() {
    echo "$DEPLOY_KUBECTL_CALLS" | grep -nF -- "$1" | head -n 1 | cut -d: -f1
}

kubectl_called() {
    [ -n "$(kubectl_call_line "$1")" ]
}

kubectl_not_called() {
    [ -z "$(kubectl_call_line "$1")" ]
}

kubectl_called_before() {
    local first second
    first=$(kubectl_call_line "$1")
    second=$(kubectl_call_line "$2")
    [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt "$second" ]
}

output_contains() {
    echo "$DEPLOY_OUTPUT" | grep -qF -- "$1"
}

deploy_exit_code_is() {
    [ "$DEPLOY_EXIT_CODE" -eq "$1" ]
}

deploy_failed() {
    [ "$DEPLOY_EXIT_CODE" -ne 0 ]
}

# Hooks of the deploy test cases

# project template naming the autoscalers consumer-<name>-hpa
hook_override_hpa_template() {
    local test_tmp="$1"
    mkdir -p "${test_tmp}/orchestration/kubernetes/manifest-templates"
    sed 's/^    name: consumer-{{NAME}}$/    name: consumer-{{NAME}}-hpa/' "${PROJECT_ROOT}/kubernetes/manifest-templates/consumer-hpa.template.yaml" \
        > "${test_tmp}/orchestration/kubernetes/manifest-templates/consumer-hpa.template.yaml"
}

# a resource registered twice fails the kustomize build of the migrate-application configuration
hook_break_migrate_application_kustomization() {
    local test_tmp="$1"
    sed -i '/resources:/a\    - ../../../deployments/redis.yaml' "${test_tmp}/var/deployment/kubernetes/kustomize/migrate-application/continuous-deploy/kustomization.yaml"
}

finish_deploy_case() {
    if [ "${DEPLOY_CASE_FAILED}" = 1 ]; then
        echo ""
        echo "kubectl calls:"
        echo "$DEPLOY_KUBECTL_CALLS" | sed 's/^/    /'
        echo "deploy output (last 30 lines):"
        echo "$DEPLOY_OUTPUT" | tail -n 30 | sed 's/^/    /'
        echo ""
    fi
    cleanup_test_env "$DEPLOY_TEST_TMP"
}

run_deploy_tests() {
    print_scenario_header "deploy (deploy.sh with mocked kubectl)"
    local migrate_apply="apply -f "  # the built migrate-application manifest is applied from a file, the other kustomizations from stdin

    print_info "Case: stale autoscalers are deleted before the apply, wanted ones are kept"
    DEPLOY_CASE_FAILED=0
    # consumer.order must not match the wanted consumer-order as a regular expression
    run_mocked_deploy consumer-autoscaling "consumer-order consumer-stale consumer.order"
    assert_deploy "deploy succeeds" deploy_exit_code_is 0
    assert_deploy "stale autoscaler consumer-stale is deleted" kubectl_called "delete horizontalpodautoscaler.autoscaling/consumer-stale"
    assert_deploy "wanted autoscaler consumer-order is kept" kubectl_not_called "delete horizontalpodautoscaler.autoscaling/consumer-order "
    assert_deploy "stale autoscaler consumer.order is deleted (not matched as a regular expression against consumer-order)" kubectl_called "delete horizontalpodautoscaler.autoscaling/consumer.order"
    assert_deploy "stale autoscaler is deleted before the apply" kubectl_called_before "delete horizontalpodautoscaler.autoscaling/consumer-stale" "${migrate_apply}${DEPLOY_TEST_TMP}/var/migrate-application.yaml"
    assert_deploy "built manifest contains the autoscalers" test "$(yq e -N 'select(.kind == "HorizontalPodAutoscaler") | .metadata.name' "${DEPLOY_TEST_TMP}/var/migrate-application.yaml" | grep -c .)" -eq 3
    finish_deploy_case

    print_info "Case: project with DEFAULT_CONSUMERS (no consumers.yaml) never touches autoscalers"
    DEPLOY_CASE_FAILED=0
    run_mocked_deploy basic-production "consumer-stale"
    assert_deploy "deploy succeeds" deploy_exit_code_is 0
    assert_deploy "autoscalers are not listed" kubectl_not_called "get hpa"
    assert_deploy "no autoscaler is deleted" kubectl_not_called "delete horizontalpodautoscaler"
    assert_deploy "migrate-application manifest is applied" kubectl_called "${migrate_apply}${DEPLOY_TEST_TMP}/var/migrate-application.yaml"
    finish_deploy_case

    print_info "Case: ENABLE_CONSUMER_AUTOSCALING=false deletes all consumer autoscalers (kill switch)"
    DEPLOY_CASE_FAILED=0
    run_mocked_deploy consumer-autoscaling-disabled "consumer-order consumer-product-recalculation"
    assert_deploy "deploy succeeds" deploy_exit_code_is 0
    assert_deploy "autoscaler consumer-order is deleted" kubectl_called "delete horizontalpodautoscaler.autoscaling/consumer-order "
    assert_deploy "autoscaler consumer-product-recalculation is deleted" kubectl_called "delete horizontalpodautoscaler.autoscaling/consumer-product-recalculation"
    assert_deploy "built manifest contains no autoscaler" test "$(yq e -N 'select(.kind == "HorizontalPodAutoscaler") | .metadata.name' "${DEPLOY_TEST_TMP}/var/migrate-application.yaml" | grep -c .)" -eq 0
    finish_deploy_case

    print_info "Case: project template naming the autoscalers differently"
    DEPLOY_CASE_FAILED=0
    # consumer-order: autoscaler of the default template, stale after the project switched to its own template
    run_mocked_deploy consumer-autoscaling "consumer-order-hpa consumer-idle-hpa consumer-product-recalculation-hpa consumer-order" hook_override_hpa_template
    assert_deploy "deploy succeeds" deploy_exit_code_is 0
    assert_deploy "renamed autoscalers are kept (matched by the name in the built manifest, not by the file name)" kubectl_not_called "delete horizontalpodautoscaler.autoscaling/consumer-order-hpa"
    assert_deploy "autoscaler of the former template is deleted" kubectl_called "delete horizontalpodautoscaler.autoscaling/consumer-order "
    finish_deploy_case

    print_info "Case: configuration failing to build deletes no autoscaler and applies nothing"
    DEPLOY_CASE_FAILED=0
    run_mocked_deploy consumer-autoscaling "consumer-order consumer-stale" "" hook_break_migrate_application_kustomization
    assert_deploy "deploy fails" deploy_failed
    assert_deploy "kustomize error is reported" output_contains "already registered id"
    assert_deploy "autoscalers are not listed" kubectl_not_called "get hpa"
    assert_deploy "no autoscaler is deleted" kubectl_not_called "delete horizontalpodautoscaler"
    assert_deploy "migrate-application manifest is not applied" kubectl_not_called "${migrate_apply}"
    finish_deploy_case

    print_info "Case: DISPLAY_FINAL_CONFIGURATION=1 prints the built configuration"
    DEPLOY_CASE_FAILED=0
    DISPLAY_FINAL_CONFIGURATION=1 run_mocked_deploy consumer-autoscaling "consumer-order"
    assert_deploy "deploy succeeds" deploy_exit_code_is 0
    assert_deploy "configuration section is printed" output_contains "migrate_application_section"
    assert_deploy "printed configuration contains the autoscalers" output_contains "kind: HorizontalPodAutoscaler"
    finish_deploy_case
}

# Main execution
main() {
    print_header "Deployment Manifest Tests"

    check_requirements

    # Clean tmp directory
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    reset_counters

    if [ "$SPECIFIC_SCENARIO" = "deploy" ]; then
        run_deploy_tests || true
    elif [ -n "$SPECIFIC_SCENARIO" ]; then
        # Run specific scenario
        run_scenario "$SPECIFIC_SCENARIO" || true
    else
        # Run all scenarios
        for scenario_dir in "${SCENARIOS_DIR}"/*/; do
            if [ -d "$scenario_dir" ] && [ -f "${scenario_dir}/deploy-project.sh" ]; then
                scenario_name=$(basename "$scenario_dir")
                run_scenario "$scenario_name" || true
            fi
        done
        run_deploy_tests || true
    fi

    print_summary
    exit $?
}

main "$@"
