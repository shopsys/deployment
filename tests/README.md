# Deployment Manifest Tests

This directory contains tests for verifying that Kubernetes manifest generation produces expected output for different environment configurations.

## Requirements

The following tools are required to run tests:

- **yq** (v3) - YAML processor
- **kustomize** - Kubernetes manifest customization
- **kubeconform** - Kubernetes manifest validation ([github.com/yannh/kubeconform](https://github.com/yannh/kubeconform))

## Quick Start

Tests should be run inside the buildpack container which contains yq v3 and kustomize. Make sure kubeconform is also available:

```bash
# List available test scenarios
docker run --rm -v $(pwd):/workspace -w /workspace \
  registry.shopsys.cz/devops/kubernetes-buildpack:1.2 \
  ./tests/run-tests.sh --list

# Run all tests
docker run --rm -v $(pwd):/workspace -w /workspace \
  registry.shopsys.cz/devops/kubernetes-buildpack:1.2 \
  ./tests/run-tests.sh

# Run a specific scenario
docker run --rm -v $(pwd):/workspace -w /workspace \
  registry.shopsys.cz/devops/kubernetes-buildpack:1.2 \
  ./tests/run-tests.sh basic-production

# Generate/update expected files
docker run --rm -v $(pwd):/workspace -w /workspace \
  registry.shopsys.cz/devops/kubernetes-buildpack:1.2 \
  ./tests/run-tests.sh --update
```

## Command Line Options

```
Usage: ./run-tests.sh [OPTIONS] [scenario-name]

Options:
  --list, -l      List available scenarios
  --update, -u    Update expected files with generated output
  --keep-tmp, -k  Keep temporary files after tests
  --help, -h      Show help message

Examples:
  ./run-tests.sh                          # Run all tests
  ./run-tests.sh basic-production         # Run specific scenario
  ./run-tests.sh --update                 # Update all expected files
  ./run-tests.sh --update basic-production  # Update specific scenario

Note: Diff output is always shown for failed tests.
```

## Directory Structure

```
tests/
├── run-tests.sh              # Main test runner script
├── lib/
│   ├── test-helpers.sh       # Helper functions
│   └── default-env.sh        # Default environment variables (shared)
├── scenarios/
│   ├── basic-production/
│   │   ├── deploy-project.sh # Deployment configuration
│   │   ├── env.sh            # Scenario-specific env overrides (optional)
│   │   ├── description.txt   # Brief description (optional)
│   │   └── expected/         # Expected output files
│   └── ...
└── tmp/                      # Temporary files (gitignored)
```

## Creating a New Test Scenario

1. Create a new directory:
   ```bash
   mkdir -p tests/scenarios/my-scenario/expected
   ```

2. Create `deploy-project.sh` (copy from existing scenario and modify):
   ```bash
   #!/bin/bash -e

   BASE_PATH="${BASE_PATH:-$(realpath "$(dirname "$0")/../../tmp/my-scenario")}"
   CONFIGURATION_TARGET_PATH="${CONFIGURATION_TARGET_PATH:-${BASE_PATH}/var/deployment/kubernetes}"
   BASIC_AUTH_PATH="${BASIC_AUTH_PATH:-${BASE_PATH}/deploy/basicHttpAuth}"
   DEPLOY_TARGET_PATH="${DEPLOY_TARGET_PATH:-${BASE_PATH}/var/deployment/deploy}"

   function generate() {
       DOMAINS=(DOMAIN_HOSTNAME_1)
       export RUNNING_PRODUCTION=1
       ENABLE_AUTOSCALING=true

       declare -A ENVIRONMENT_VARIABLES=(
           ["APP_SECRET"]="${APP_SECRET}"
           # ... use variables from default-env.sh
       )

       declare -A CRON_INSTANCES=(
           ["cron"]='*/5 * * * *'
       )

       VARS=(TAG STOREFRONT_TAG PROJECT_NAME BASE_PATH ...)

       source "${DEPLOY_TARGET_PATH}/functions.sh"
       source "${DEPLOY_TARGET_PATH}/parts/domains.sh"
       source "${DEPLOY_TARGET_PATH}/parts/domain-rabbitmq-management.sh"
       source "${DEPLOY_TARGET_PATH}/parts/environment-variables.sh"
       source "${DEPLOY_TARGET_PATH}/parts/kubernetes-variables.sh"
       source "${DEPLOY_TARGET_PATH}/parts/cron.sh"
       source "${DEPLOY_TARGET_PATH}/parts/autoscaling.sh"
       # NOTE: deploy.sh is NOT sourced - it contains kubectl commands
   }

   function merge() {
       DEFAULT_CONSUMERS=("email:email_transport:1")
       source "${BASE_PATH}/vendor/shopsys/deployment/deploy/functions.sh"
       merge_configuration
       create_consumer_manifests "${DEFAULT_CONSUMERS[@]}"
   }

   case "$1" in
       "generate") merge; generate ;;
       "merge") merge ;;
       *) echo "invalid option"; exit 1 ;;
   esac
   ```

3. (Optional) Create `env.sh` for scenario-specific variable overrides:
   ```bash
   #!/bin/bash
   # Only override what differs from lib/default-env.sh
   export PROJECT_NAME="my-project"
   export DOMAIN_HOSTNAME_1="www.my-domain.com"
   ```

4. Generate expected output:
   ```bash
   docker run --rm -v $(pwd):/workspace -w /workspace \
     registry.shopsys.cz/devops/kubernetes-buildpack:1.2 \
     ./tests/run-tests.sh --update my-scenario
   ```

5. Run tests to verify:
   ```bash
   docker run --rm -v $(pwd):/workspace -w /workspace \
     registry.shopsys.cz/devops/kubernetes-buildpack:1.2 \
     ./tests/run-tests.sh my-scenario
   ```

## Environment Variables

### Default Variables (`lib/default-env.sh`)

Common variables shared by all scenarios:
- `TAG`, `STOREFRONT_TAG` - Docker image tags
- `POSTGRES_DATABASE_*` - Database connection
- `S3_ENDPOINT`, `S3_SECRET` - Storage
- `ELASTICSEARCH_URLS` - Search
- `RABBITMQ_*` - Message queue
- etc.

### Scenario Overrides (`env.sh`)

Each scenario can override defaults:
- `PROJECT_NAME` - Required, format: `name-environment`
- `DOMAIN_HOSTNAME_*` - Domain hostnames
- Any other variable from default-env.sh

## Output Files

| File | Description |
|------|-------------|
| `webserver.yaml` | Combined webserver kustomize output |
| `migrate-continuous-deploy.yaml` | Migration job for continuous deployment |
| `migrate-first-deploy.yaml` | Migration job for first deployment |
| `migrate-first-deploy-with-demo-data.yaml` | First deploy with demo data |
| `cron.yaml` | Cron deployment kustomize output |
| `horizontalPodAutoscaler.yaml` | Backend HPA configuration |
| `horizontalStorefrontAutoscaler.yaml` | Frontend HPA configuration |
| `namespace.yaml` | Namespace definition |

## How It Works

1. **Setup**: Creates mock project structure in `tests/tmp/{scenario}/`
2. **Environment**: Loads `lib/default-env.sh`, then scenario's `env.sh` (if exists)
3. **Merge**: Runs `deploy-project.sh merge` to copy base manifests
4. **Generate**: Runs `deploy-project.sh generate` to configure manifests
5. **Build**: Uses kustomize to build final manifests
6. **Compare**: Compares generated output against expected files

## Tips

- Diff output is automatically shown for failing tests
- Run `--update` after making intentional changes to manifest templates
- Keep scenarios focused on specific configurations
- The `deploy-project.sh` should mirror your actual deployment script structure
