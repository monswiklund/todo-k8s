#!/bin/bash

set -e

IMAGE_TAG=${1:-"codecrasher2/todoapp:latest"}
SERVICE_NAME="todoapp_todoapp"
STACK_NAME="todoapp"

echo "=== Deployment Started ==="
echo "Image: $IMAGE_TAG"

# Pull image
if ! docker pull "$IMAGE_TAG"; then
    echo "ERROR: Failed to pull image"
    exit 1
fi

# Check if service exists
if docker service inspect "$SERVICE_NAME" >/dev/null 2>&1; then
    echo "Updating service..."
    if ! docker service update --image "$IMAGE_TAG" "$SERVICE_NAME"; then
        echo "ERROR: Service update failed"
        exit 1
    fi
else
    echo "Deploying stack..."
    if [ ! -f "docker-compose.yml" ]; then
        echo "ERROR: docker-compose.yml not found"
        exit 1
    fi
    if ! docker stack deploy -c docker-compose.yml "$STACK_NAME"; then
        echo "ERROR: Stack deployment failed"
        exit 1
    fi
fi

echo "=== Deployment Complete ==="
docker service ps "$SERVICE_NAME"