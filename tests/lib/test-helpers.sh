#!/bin/bash

# Test helper functions for deployment manifest testing

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
NO_COLOR='\e[39m'
BOLD='\e[1m'
RESET='\e[0m'

# Counter for test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NO_COLOR} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NO_COLOR} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NO_COLOR} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NO_COLOR} $1"
}

print_header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD} $1${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
}

print_scenario_header() {
    echo ""
    echo -e "${BOLD}───────────────────────────────────────────────────────────${RESET}"
    echo -e "${BOLD} Scenario: $1${RESET}"
    echo -e "${BOLD}───────────────────────────────────────────────────────────${RESET}"
}

# Compare two YAML files
# Returns 0 if identical, 1 if different
compare_yaml() {
    local expected="$1"
    local actual="$2"
    local name="$3"

    if [ ! -f "$expected" ]; then
        print_warning "Expected file not found: $expected"
        ((TESTS_SKIPPED++))
        return 2
    fi

    if [ ! -f "$actual" ]; then
        print_error "Generated file not found: $actual"
        ((TESTS_FAILED++))
        return 1
    fi

    # Use diff to compare
    if diff -q "$expected" "$actual" > /dev/null 2>&1; then
        print_success "$name"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$name"
        ((TESTS_FAILED++))

        # Always show diff on failure
        echo ""
        diff -u "$expected" "$actual" | head -100
        echo ""
        return 1
    fi
}

# Compare directories containing YAML files
compare_directories() {
    local expected_dir="$1"
    local actual_dir="$2"
    local prefix="${3:-}"

    if [ ! -d "$expected_dir" ]; then
        print_warning "Expected directory not found: $expected_dir"
        return 2
    fi

    # Find all YAML files in expected directory
    while IFS= read -r -d '' expected_file; do
        local relative_path="${expected_file#$expected_dir/}"
        local actual_file="$actual_dir/$relative_path"
        local test_name="${prefix}${relative_path}"

        compare_yaml "$expected_file" "$actual_file" "$test_name"
    done < <(find "$expected_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
}

# Build kustomize output for a given path
build_kustomize() {
    local kustomize_path="$1"
    local output_file="$2"

    if command -v kustomize &> /dev/null; then
        # Try newer syntax first, fall back to older underscore syntax
        kustomize build --load-restrictor LoadRestrictionsNone "$kustomize_path" > "$output_file" 2>&1 || \
        kustomize build --load_restrictor none "$kustomize_path" > "$output_file" 2>&1
    else
        # Fallback to kubectl kustomize
        kubectl kustomize --load-restrictor LoadRestrictionsNone "$kustomize_path" > "$output_file" 2>&1 || \
        kubectl kustomize --load_restrictor none "$kustomize_path" > "$output_file" 2>&1
    fi
}

# Reset test counters
reset_counters() {
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
}

# Print test summary
print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD} Test Summary${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "  ${GREEN}Passed:${NO_COLOR}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NO_COLOR}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NO_COLOR} $TESTS_SKIPPED"
    echo -e "  Total:   $total"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}${BOLD}All tests passed!${RESET}"
        return 0
    else
        echo -e "${RED}${BOLD}Some tests failed!${RESET}"
        return 1
    fi
}

# Cleanup function
cleanup_test_env() {
    local test_tmp_dir="$1"
    if [ -d "$test_tmp_dir" ] && [ "$KEEP_TMP" != "1" ]; then
        rm -rf "$test_tmp_dir"
    fi
}