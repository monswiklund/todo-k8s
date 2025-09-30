#!/bin/bash

set -e

echo "=== Initial Deployment Script ==="
echo "This script deploys the TodoApp for the first time to a fresh Swarm cluster"
echo ""

# Configuration
BASTION_HOST=${1:-$(terraform -chdir=terraform output -raw bastion_public_ip 2>/dev/null)}
MANAGER_IP=${2:-$(terraform -chdir=terraform output -raw manager_ips | grep private | awk '{print $3}' | tr -d '",' 2>/dev/null)}
IMAGE="${3:-codecrasher2/todoapp:latest}"

if [ -z "$BASTION_HOST" ] || [ -z "$MANAGER_IP" ]; then
    echo "ERROR: Could not determine bastion or manager IP"
    echo "Usage: $0 [BASTION_HOST] [MANAGER_PRIVATE_IP] [IMAGE]"
    echo ""
    echo "Or run from terraform directory where 'terraform output' works"
    exit 1
fi

echo "Bastion Host: $BASTION_HOST"
echo "Manager IP: $MANAGER_IP"
echo "Image: $IMAGE"
echo ""

# Check SSH key
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "ERROR: SSH key not found at ~/.ssh/id_rsa"
    exit 1
fi

# Copy deployment files to manager
echo "Copying deployment files to manager..."
scp -o StrictHostKeyChecking=accept-new \
    -o ProxyJump=ec2-user@$BASTION_HOST \
    docker-compose.yml \
    scripts/deploy.sh \
    ec2-user@$MANAGER_IP:~/

echo "Files copied successfully"
echo ""

# Deploy stack
echo "Deploying stack to Swarm..."
ssh -o StrictHostKeyChecking=accept-new \
    -J ec2-user@$BASTION_HOST \
    ec2-user@$MANAGER_IP << EOF

echo "Checking Swarm status..."
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
    echo "ERROR: Swarm is not active"
    exit 1
fi

echo "Swarm nodes:"
docker node ls

echo ""
echo "Pulling Docker image..."
docker pull $IMAGE

echo ""
echo "Deploying stack..."
chmod +x ~/deploy.sh
~/deploy.sh "$IMAGE"

EOF

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Checking deployment status..."

# Get ALB DNS
ALB_DNS=$(terraform -chdir=terraform output -raw alb_dns_name 2>/dev/null || echo "")

if [ -n "$ALB_DNS" ]; then
    echo ""
    echo "Application URLs:"
    echo "  Main app: http://$ALB_DNS"
    echo "  Health:   http://$ALB_DNS/health"
    echo "  Swagger:  http://$ALB_DNS/swagger"
    echo ""
    echo "Note: It may take 2-3 minutes for health checks to pass"
    echo ""

    # Optional: Wait for health check
    read -p "Wait for health checks to pass? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Waiting for health checks..."
        for i in {1..24}; do
            if curl -f -s -m 5 "http://$ALB_DNS/health" >/dev/null 2>&1; then
                echo "✓ Application is healthy!"
                exit 0
            fi
            echo "Attempt $i/24 - waiting 10s..."
            sleep 10
        done
        echo "Health checks did not pass within 4 minutes"
        echo "Check ALB target health: aws elbv2 describe-target-health --target-group-arn \$(terraform output -raw target_group_arn)"
    fi
fi