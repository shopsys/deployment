# Deployment Manifest Tests

Tests for verifying Kubernetes manifest generation produces expected output.

## Quick Start

```bash
# Run all tests
docker run --rm --user "$(id -u):$(id -g)" -v "$(pwd)":/workspace -w /workspace \
  shopsys/kubernetes-buildpack:2.0 \
  ./tests/run-tests.sh

# Run specific scenario
docker run --rm --user "$(id -u):$(id -g)" -v "$(pwd)":/workspace -w /workspace \
  shopsys/kubernetes-buildpack:2.0 \
  ./tests/run-tests.sh basic-production

# Update expected files after intentional changes
docker run --rm --user "$(id -u):$(id -g)" -v "$(pwd)":/workspace -w /workspace \
  shopsys/kubernetes-buildpack:2.0 \
./tests/run-tests.sh --update

# List available scenarios
docker run --rm --user "$(id -u):$(id -g)" -v "$(pwd)":/workspace -w /workspace \
  shopsys/kubernetes-buildpack:2.0 \
./tests/run-tests.sh --list
```

Using `--user "$(id -u):$(id -g)"` ensures generated files are owned by your local user instead of `root`.

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
├── fixtures/                 # Shared project-level overrides copied to tmp test project
├── lib/
│   ├── test-helpers.sh       # Helper functions
│   └── default-env.sh        # Shared default environment variables
└── scenarios/
    └── {scenario-name}/
        ├── deploy-project.sh # Scenario configuration (required)
        ├── env.sh            # Environment overrides (optional)
        ├── consumers.yaml    # Optional consumer declaration copied to deploy/consumers.yaml of the mock project
        ├── expected-error.txt # Optional: the scenario must fail during generation with every line of this file in its output (no expected/ then)
        └── expected/         # Expected output files
```

## Creating a New Scenario

1. Copy an existing scenario directory
2. Modify `env.sh` with scenario-specific variables (PROJECT_NAME, DOMAIN_HOSTNAME_*, etc.)
3. Modify `deploy-project.sh` for scenario-specific configuration (DOMAINS, CRON_INSTANCES, CONSUMERS, etc.)
   - Instead of `DEFAULT_CONSUMERS`, a scenario may provide `consumers.yaml` (the `deploy/consumers.yaml` format
     read by `deploy/parts/consumers.sh`); it is copied into the mock project and `DEFAULT_CONSUMERS` must then be omitted
   - A scenario expecting a failure provides `expected-error.txt` instead of `expected/`, see `merge-phase-failure` or `consumers-invalid-fields`
4. Generate expected files: `./tests/run-tests.sh --update my-scenario`
5. Verify: `./tests/run-tests.sh my-scenario`

## How It Works

1. Creates mock project structure in `tests/tmp/{scenario}/`
2. Loads `lib/default-env.sh`, then scenario's `env.sh`
3. Runs scenario's `deploy-project.sh merge` and `deploy-project.sh generate` as two separate `bash -e` processes, like the image build
   and the CI job of a real project; a failure of either phase fails the scenario (a scenario with `expected-error.txt` ends here:
   it passes when one of the phases fails with the expected text)
4. Builds kustomize outputs (a failed build fails the scenario and prints the kustomize error)
5. Checks invariants of the generated consumer manifests that do not depend on the expected files
   (every consumer has environment variables, replicas are owned either by the deployment or by its autoscaler,
   every autoscaler targets a generated deployment and watches at least one queue)
6. Compares with expected files

The expected files only prove that the output is deterministic, not that it is correct: `--update` records whatever was generated.
Read the diff of the expected files after `--update` as a code review, and when a new scenario is added, compare its output
with an existing scenario for the same kind of object (e.g. a consumer deployment must look the same regardless of where it was declared).
The invariants in step 5 guard against the classes of mistakes that already slipped through this way.

`tests/fixtures/orchestration/kubernetes/configmap/nginx.yaml` is intentionally tracked because the deployment package no longer ships `kubernetes/configmap/nginx.yaml`, but test scenarios still need a project-level override to build webserver manifests.
