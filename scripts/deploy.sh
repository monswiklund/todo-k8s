#!/bin/bash

set -e

IMAGE_TAG=${1:-"codecrasher2/todoapp:latest"}
SERVICE_NAME="todoapp_todoapp"
STACK_NAME="todoapp"

echo "=== Deployment Started at $(date) ==="
echo "Image: $IMAGE_TAG"
echo "Service: $SERVICE_NAME"

# Check Docker Swarm
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
    echo "ERROR: Node is not part of Docker Swarm"
    exit 1
fi

# Check if manager node
if ! docker node ls >/dev/null 2>&1; then
    echo "ERROR: Must run on manager node"
    exit 1
fi

# Pull latest image
echo "Pulling image..."
docker pull "$IMAGE_TAG"

# Check if service exists
if docker service inspect "$SERVICE_NAME" >/dev/null 2>&1; then
    # Service exists - perform rolling update
    echo "Service exists - performing rolling update..."
    docker service update \
        --image "$IMAGE_TAG" \
        --update-parallelism 1 \
        --update-delay 10s \
        --update-failure-action rollback \
        --update-monitor 60s \
        "$SERVICE_NAME"
else
    # Service doesn't exist - deploy stack
    echo "Service not found - deploying new stack..."
    if [ ! -f "docker-compose.yml" ]; then
        echo "ERROR: docker-compose.yml not found"
        exit 1
    fi
    docker stack deploy -c docker-compose.yml "$STACK_NAME"
fi

# Wait for deployment to stabilize
echo "Waiting for deployment to stabilize..."
sleep 10

# Monitor deployment
for i in {1..30}; do
    # Get replica counts
    REPLICAS=$(docker service inspect "$SERVICE_NAME" \
        --format "{{.Spec.Mode.Replicated.Replicas}}" 2>/dev/null || echo "0")

    RUNNING=$(docker service ps "$SERVICE_NAME" \
        --filter "desired-state=running" \
        --filter "current-state=running" \
        --no-trunc 2>/dev/null | grep -c "Running" || echo "0")

    echo "Progress: $RUNNING/$REPLICAS replicas running"

    if [ "$RUNNING" -eq "$REPLICAS" ] && [ "$REPLICAS" != "0" ]; then
        echo "=== Deployment Successful at $(date) ==="

        # Show service status
        echo ""
        echo "Service status:"
        docker service ps "$SERVICE_NAME" --filter "desired-state=running"

        exit 0
    fi

    sleep 10
done

# Deployment timeout
echo "ERROR: Deployment timeout after 5 minutes"
echo ""
echo "Service tasks:"
docker service ps "$SERVICE_NAME" --no-trunc

exit 1