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

    # Create domains_urls.yaml.dist dynamically based on domain count
    echo "domains_urls:" > "${test_tmp}/config/domains_urls.yaml.dist"
    for i in $(seq 1 ${domain_count}); do
        echo "    -   id: ${i}" >> "${test_tmp}/config/domains_urls.yaml.dist"
        echo "        url: ~" >> "${test_tmp}/config/domains_urls.yaml.dist"
    done

    # Create basicHttpAuth file (required by deploy.sh)
    mkdir -p "${test_tmp}/deploy"
    echo "testuser:\$apr1\$test\$hashedpassword" > "${test_tmp}/deploy/basicHttpAuth"

    echo "$test_tmp"
}

# Build kustomize outputs
build_outputs() {
    local test_tmp="$1"
    local output_dir="${test_tmp}/output"

    mkdir -p "$output_dir"

    local config_path="${test_tmp}/var/deployment/kubernetes"

    # Build webserver kustomize output
    if [ -d "${config_path}/kustomize/webserver" ]; then
        build_kustomize "${config_path}/kustomize/webserver" "${output_dir}/webserver.yaml" || true
    fi

    # Build migrate-application outputs for each type
    for deploy_type in continuous-deploy first-deploy first-deploy-with-demo-data; do
        if [ -d "${config_path}/kustomize/migrate-application/${deploy_type}" ]; then
            build_kustomize "${config_path}/kustomize/migrate-application/${deploy_type}" \
                "${output_dir}/migrate-${deploy_type}.yaml" || true
        fi
    done

    # Build cron kustomize output
    if [ -d "${config_path}/kustomize/cron" ]; then
        build_kustomize "${config_path}/kustomize/cron" "${output_dir}/cron.yaml" || true
    fi

    echo "$output_dir"
}

# Run a single test scenario
run_scenario() {
    local scenario_name="$1"
    local scenario_dir="${SCENARIOS_DIR}/${scenario_name}"

    print_scenario_header "$scenario_name"

    # Validate scenario exists
    if [ ! -d "$scenario_dir" ]; then
        print_error "Scenario not found: $scenario_name"
        return 1
    fi

    if [ ! -f "${scenario_dir}/deploy-project.sh" ]; then
        print_error "Missing deploy-project.sh in scenario: $scenario_name"
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

    # Export environment variables and run deploy-project.sh
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

        # Run the scenario's deploy-project.sh
        bash "${scenario_dir}/deploy-project.sh" generate
    )

    # Build kustomize outputs
    print_info "Building kustomize outputs..."
    local output_dir
    output_dir=$(build_outputs "$test_tmp")

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
        run_scenario "$SPECIFIC_SCENARIO"
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
