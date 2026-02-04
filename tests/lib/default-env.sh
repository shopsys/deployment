#!/bin/bash

# Default environment variables for all test scenarios
# These simulate typical CI/CD variables

# Project defaults (scenarios should override PROJECT_NAME and DOMAIN_COUNT)
export TAG="v1.0.0"
export STOREFRONT_TAG="v1.0.0"
export DOMAIN_COUNT=1

# Database
export POSTGRES_DATABASE_IP_ADDRESS="10.0.0.100"
export POSTGRES_DATABASE_PORT="5432"
export POSTGRES_DATABASE_PASSWORD="test-db-password"

# Application
export APP_SECRET="test-app-secret-key"

# S3 Storage
export S3_ENDPOINT="https://s3.example.com"
export S3_SECRET="test-s3-secret"

# Elasticsearch
export ELASTICSEARCH_URLS="http://elasticsearch:9200"

# Messaging
export MESSENGER_TRANSPORT_DSN="amqp://guest:guest@rabbitmq:5672/%2f/messages"
export MAILER_DSN="smtp://mailhog:1025"

# RabbitMQ
export RABBITMQ_DEFAULT_USER="rabbitmq"
export RABBITMQ_DEFAULT_PASS="rabbitmq-password"
export RABBITMQ_IP_WHITELIST="10.0.0.0/8"

# Registry (for simulation)
export DEPLOY_REGISTER_USER="deploy-user"
export DEPLOY_REGISTER_PASSWORD="deploy-password"
export CI_REGISTRY="registry.example.com"
