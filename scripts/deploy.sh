#!/bin/bash

# Docker Swarm Deployment Script with ALB Support
# Usage: ./deploy.sh [IMAGE_TAG] [SERVICE_NAME]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
IMAGE_TAG=${1:-"codecrasher2/todoapp:latest"}
SERVICE_NAME=${2:-"todoapp_todoapp"}
TIMEOUT=${3:-300}  # 5 minutes default timeout

echo -e "${GREEN}=== Docker Swarm Deployment Started ===${NC}"
echo "Image: $IMAGE_TAG"
echo "Service: $SERVICE_NAME"
echo "Timeout: ${TIMEOUT}s"
echo "Timestamp: $(date)"

# Function for logging
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"
}

# Function to check if we're in a Docker Swarm
check_swarm() {
    if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        error "This node is not part of an active Docker Swarm"
        exit 1
    fi
    log "Docker Swarm is active"
}

# Main deployment logic
main() {
    log "Starting deployment process"

    # Pre-deployment checks
    check_swarm

    # Validate Docker image accessibility
    log "Validating Docker image: $IMAGE_TAG"
    if ! docker pull "$IMAGE_TAG" >/dev/null 2>&1; then
        error "Failed to pull Docker image: $IMAGE_TAG"
        error "Please ensure the image exists and is accessible"
        return 1
    fi
    log "Docker image validated successfully"

    # Update docker-compose.yml with new image
    if [ -f "docker-compose.yml" ]; then
        log "Updating docker-compose.yml with image: $IMAGE_TAG"
        sed -i.bak "s|image:.*|image: $IMAGE_TAG|g" docker-compose.yml
    fi

    # Check if service exists
    if ! docker service ls --format "{{.Name}}" | grep -q "^${SERVICE_NAME}$"; then
        warn "Service $SERVICE_NAME not found. Creating new service..."

        # Create new service from docker-compose.yml stack
        if [ -f "docker-compose.yml" ]; then
            log "Deploying stack from docker-compose.yml..."
            docker stack deploy -c docker-compose.yml todoapp

            # Wait for initial deployment
            log "Waiting for initial service creation..."
            sleep 45
        else
            error "docker-compose.yml not found. Cannot create service."
            exit 1
        fi
    else
        log "Updating existing service..."

        # Update service with new image
        docker service update \
            --image "$IMAGE_TAG" \
            --update-delay 10s \
            --update-parallelism 1 \
            --update-order start-first \
            --detach \
            "$SERVICE_NAME"
    fi

    # Wait for deployment to stabilize
    log "Waiting for deployment to complete..."
    wait_for_service_stable

    # Verify deployment
    verify_deployment

    log "Deployment completed successfully!"
}

# Function to wait for service to be stable
wait_for_service_stable() {
    local timeout_count=0
    local max_timeout=$((TIMEOUT / 10))

    while [ $timeout_count -lt $max_timeout ]; do
        local running_tasks
        running_tasks=$(docker service ps "$SERVICE_NAME" --filter "desired-state=running" --format "{{.CurrentState}}" | grep -c "Running" || echo "0")
        local desired_replicas
        desired_replicas=$(docker service inspect "$SERVICE_NAME" --format "{{.Spec.Mode.Replicated.Replicas}}")

        log "Running tasks: $running_tasks/$desired_replicas"

        if [ "$running_tasks" -eq "$desired_replicas" ]; then
            log "All replicas are running!"
            return 0
        fi

        sleep 10
        timeout_count=$((timeout_count + 1))
    done

    error "Timeout waiting for service to be stable"
    return 1
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."

    # Check service status
    docker service ps "$SERVICE_NAME" --no-trunc

    # Check running tasks
    local running_tasks
    running_tasks=$(docker service ps "$SERVICE_NAME" --filter "desired-state=running" --format "{{.CurrentState}}" | grep -c "Running" || echo "0")

    if [ "$running_tasks" -gt 0 ]; then
        log "Service is running with $running_tasks healthy tasks"

        # Display recent logs
        log "Recent service logs:"
        docker service logs "$SERVICE_NAME" --tail 20 --timestamps

        # Show final service status
        log "Final service status:"
        docker service ls --filter "name=$SERVICE_NAME"

        return 0
    else
        error "Deployment failed - no healthy tasks running"
        error "Debug information:"
        docker service ps "$SERVICE_NAME" --no-trunc
        docker service logs "$SERVICE_NAME" --tail 50

        # JSON error output for CI/CD
        if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
            echo "::group::Deployment Error JSON"
            cat << ERROR_JSON_EOF
{
  "status": "failed",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "image": "$IMAGE_TAG",
  "service": "$SERVICE_NAME",
  "error": "No healthy tasks running",
  "running_tasks": $(docker service ps "$SERVICE_NAME" --filter "desired-state=running" --format "{{.CurrentState}}" | grep -c "Running" || echo "0"),
  "deployment_duration": "${SECONDS}s"
}
ERROR_JSON_EOF
            echo "::endgroup::"
        fi

        return 1
    fi
}

# Cleanup function
cleanup() {
    if [ -f "docker-compose.yml.bak" ]; then
        log "Restoring original docker-compose.yml"
        mv docker-compose.yml.bak docker-compose.yml
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main

# Exit with success
log "Deployment completed successfully!"
echo -e "${GREEN}=== Deployment Summary ===${NC}"
echo "Image deployed: $IMAGE_TAG"
echo "Service: $SERVICE_NAME"
echo "Timestamp: $(date)"

# JSON status output for CI/CD parsing
if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    echo "::group::Deployment Status JSON"
    cat << JSON_EOF
{
  "status": "success",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "image": "$IMAGE_TAG",
  "service": "$SERVICE_NAME",
  "running_tasks": $(docker service ps "$SERVICE_NAME" --filter "desired-state=running" --format "{{.CurrentState}}" | grep -c "Running" || echo "0"),
  "deployment_duration": "${SECONDS}s"
}
JSON_EOF
    echo "::endgroup::"
fi