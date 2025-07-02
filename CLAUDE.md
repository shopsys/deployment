# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Shopsys Platform deployment package - a library that simplifies Kubernetes deployment for Shopsys Platform e-commerce applications. It provides deployment scripts, Kubernetes manifests, and configuration tools for orchestrating deployments in production and development environments.

## Common Commands

### Deployment Commands

Deploy to production:
```bash
./deploy/deploy-project.sh deploy
```

Merge configurations (prepare Kubernetes manifests):
```bash
./deploy/deploy-project.sh merge
```

### Development Workflow

1. **Before deployment**: Ensure all required environment variables are set in GitLab CI/CD
2. **First deployment**: Set `FIRST_DEPLOY=1` environment variable
3. **Continuous deployment**: Use `FIRST_DEPLOY=0` for subsequent deployments

### Testing & Validation

Check if deployment configuration is valid:
```bash
kubectl apply --dry-run=client -f kubernetes/namespace.yaml
```

View generated Kubernetes configurations:
```bash
DISPLAY_FINAL_CONFIGURATION=1 ./deploy/deploy-project.sh deploy
```

## High-Level Architecture

### Core Components

1. **Deployment Scripts** (`deploy/`)
   - `deploy-project.sh`: Main deployment entry point
   - `functions.sh`: Shared utility functions
   - `parts/`: Modular deployment components
     - `domains.sh`: Domain configuration
     - `environment-variables.sh`: Environment variable management
     - `deploy.sh`: Core deployment logic
     - `cron.sh`: Cron job configuration
     - `autoscaling.sh`: Horizontal pod autoscaling

2. **Kubernetes Manifests** (`kubernetes/`)
   - `deployments/`: Application deployments (webserver, php-fpm, redis, rabbitmq, cron)
   - `configmap/`: Configuration files for services
   - `services/`: Kubernetes service definitions
   - `kustomize/`: Kustomization overlays for different deployment scenarios

3. **Deployment Flow**
   - Namespace creation and secret management
   - Database migrations via temporary job pod
   - Rolling deployment of webserver/PHP-FPM containers
   - Storefront deployment (Next.js application)
   - Optional horizontal pod autoscaling
   - Health checks and maintenance mode management

### Key Concepts

- **Multi-Domain Support**: Configure multiple domains via `DOMAIN_HOSTNAME_*` variables
- **Environment Separation**: Different configurations for production vs development
- **HTTP Auth**: Optional basic authentication for non-production environments
- **Consumer Workers**: Background job processing via RabbitMQ
- **Slack Notifications**: Optional deployment status notifications

### Integration Points

- **GitLab CI/CD**: Primary deployment trigger
- **Docker Registry**: Image storage (supports GitLab Registry or GCR)
- **External Services**:
  - PostgreSQL database
  - Elasticsearch
  - S3-compatible storage
  - RabbitMQ message broker
  - Redis cache

### Customization

Override default Kubernetes manifests by placing custom versions in:
```
orchestration/kubernetes/
```

The deployment system will automatically use your custom manifests instead of the defaults.