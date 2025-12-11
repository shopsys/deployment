# Deployment Manifest Tests

Tests for verifying Kubernetes manifest generation produces expected output.

## Quick Start

```bash
# Run all tests
docker run --rm -v $(pwd):/workspace -w /workspace \
  shopsys/kubernetes-buildpack:1.2 \
  ./tests/run-tests.sh

# Run specific scenario
docker run --rm -v $(pwd):/workspace -w /workspace \
  shopsys/kubernetes-buildpack:1.2 \
  ./tests/run-tests.sh basic-production

# Update expected files after intentional changes
docker run --rm -v $(pwd):/workspace -w /workspace \
  shopsys/kubernetes-buildpack:1.2 \
./tests/run-tests.sh --update

# List available scenarios
docker run --rm -v $(pwd):/workspace -w /workspace \
  shopsys/kubernetes-buildpack:1.2 \
./tests/run-tests.sh --list
```

## Options

```
--list, -l      List available scenarios
--update, -u    Update expected files with generated output
--keep-tmp, -k  Keep temporary files after tests
--help, -h      Show help message
```

## Directory Structure

```
tests/
├── run-tests.sh              # Main test runner
├── lib/
│   ├── test-helpers.sh       # Helper functions
│   └── default-env.sh        # Shared default environment variables
└── scenarios/
    └── {scenario-name}/
        ├── deploy-project.sh # Scenario configuration (required)
        ├── env.sh            # Environment overrides (optional)
        └── expected/         # Expected output files
```

## Creating a New Scenario

1. Copy an existing scenario directory
2. Modify `env.sh` with scenario-specific variables (PROJECT_NAME, DOMAIN_HOSTNAME_*, etc.)
3. Modify `deploy-project.sh` for scenario-specific configuration (DOMAINS, CRON_INSTANCES, CONSUMERS, etc.)
4. Generate expected files: `./tests/run-tests.sh --update my-scenario`
5. Verify: `./tests/run-tests.sh my-scenario`

## How It Works

1. Creates mock project structure in `tests/tmp/{scenario}/`
2. Loads `lib/default-env.sh`, then scenario's `env.sh`
3. Runs scenario's `deploy-project.sh generate`
4. Builds kustomize outputs
5. Compares with expected files
