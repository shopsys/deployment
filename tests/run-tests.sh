#!/bin/bash
set -e

# Deployment Manifest Test Runner
# ================================
# This script runs test scenarios to verify Kubernetes manifest generation.
#
# Usage:
#   ./run-tests.sh                    # Run all scenarios
#   ./run-tests.sh scenario-name      # Run specific scenario
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

# Main execution
main() {
    print_header "Deployment Manifest Tests"

    check_requirements

    # Clean tmp directory
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    reset_counters

    if [ -n "$SPECIFIC_SCENARIO" ]; then
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
    fi

    print_summary
    exit $?
}

main "$@"
