#!/bin/bash

set -e

IMAGE_TAG=${1:-"codecrasher2/todoapp:latest"}
SERVICE_NAME=${2:-"todoapp_todoapp"}

echo "Deploying $IMAGE_TAG to $SERVICE_NAME"

# Check Docker Swarm
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
    echo "ERROR: Not in Docker Swarm"
    exit 1
fi

# Pull image
docker pull "$IMAGE_TAG"

# Update docker-compose.yml
if [ -f "docker-compose.yml" ]; then
    sed -i.bak "s|image:.*|image: $IMAGE_TAG|g" docker-compose.yml
fi

# Always redeploy stack to ensure configuration changes are applied
echo "Redeploying stack to apply configuration changes"
docker stack deploy -c docker-compose.yml todoapp

# Wait for deployment
echo "Waiting for deployment..."
for i in {1..30}; do
    # Count running tasks properly
    running=$(docker service ps "$SERVICE_NAME" \
        --filter "desired-state=running" \
        --format "{{.CurrentState}}" | \
        grep -c "Running" 2>/dev/null || echo 0)
    
    desired=$(docker service inspect "$SERVICE_NAME" \
        --format "{{.Spec.Mode.Replicated.Replicas}}")

    echo "Status: $running/$desired tasks running"

    if [ "$running" -eq "$desired" ] 2>/dev/null; then
        echo "Deployment successful!"
        exit 0
    fi

    sleep 10
done

echo "Deployment timeout"
docker service ps "$SERVICE_NAME" --no-trunc
exit 1