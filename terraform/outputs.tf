# ALB URLs (Primary access points)
output "application_url" {
  description = "Main application URL via ALB"
  value       = "http://${aws_lb.todo_alb.dns_name}"
}

output "swagger_url" {
  description = "API documentation URL via ALB"
  value       = "http://${aws_lb.todo_alb.dns_name}/swagger"
}

# ALB Information
output "alb_dns_name" {
  description = "ALB DNS name for CI/CD"
  value       = aws_lb.todo_alb.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for Route 53"
  value       = aws_lb.todo_alb.zone_id
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.todo_manager_tg.arn
}

# Direct access URLs (backup/debugging)
output "direct_manager_url" {
  description = "Direct manager node URL (bypass ALB)"
  value       = "http://${aws_instance.swarm_manager.public_ip}:8080"
}

# SSH access
output "ssh_manager" {
  description = "SSH to manager node"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.swarm_manager.public_ip}"
}

output "ssh_workers" {
  description = "SSH to worker nodes"
  value = [
    for i, instance in aws_instance.swarm_workers :
    "ssh -i ~/.ssh/id_rsa ec2-user@${instance.public_ip}  # worker-${i + 1}"
  ]
}

# Node IPs
output "manager_ips" {
  description = "Manager node IPs"
  value = {
    public  = aws_instance.swarm_manager.public_ip
    private = aws_instance.swarm_manager.private_ip
  }
}

output "worker_ips" {
  description = "Worker node IPs"
  value = {
    public  = aws_instance.swarm_workers[*].public_ip
    private = aws_instance.swarm_workers[*].private_ip
  }
}

# Essential commands
output "commands" {
  description = "Key management commands"
  value = {
    check_nodes    = "docker node ls"
    check_services = "docker service ls"
    update_app     = "docker service update --image codecrasher2/todoapp:latest todoapp_todoapp"
    view_logs      = "docker service logs todoapp_todoapp --tail 20"
    deploy_script  = "./scripts/deploy.sh codecrasher2/todoapp:latest"
    health_check = "curl -f http://${aws_lb.todo_alb.dns_name}/health"
  }
}

# Bastion Host Information
output "bastion_public_ip" {
  description = "Bastion host public IP (Elastic IP)"
  value       = aws_eip.bastion_eip.public_ip
}

output "bastion_public_dns" {
  description = "Bastion host public DNS name"
  value       = aws_instance.bastion.public_dns
}

output "ssh_bastion" {
  description = "SSH command to connect to bastion host"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_eip.bastion_eip.public_ip}"
}

output "ssh_manager_via_bastion" {
  description = "SSH command to connect to manager via bastion"
  value       = "ssh -i ~/.ssh/id_rsa -J ec2-user@${aws_eip.bastion_eip.public_ip} ec2-user@${aws_instance.swarm_manager.private_ip}"
}

# CI/CD Secrets Information (Updated for Bastion)
output "github_secrets_required" {
  description = "Required GitHub Secrets for CI/CD with Bastion"
  value = {
    DOCKER_USERNAME    = "Docker Hub username"
    DOCKER_PASSWORD    = "Docker Hub access token"
    DEPLOY_KEY         = "SSH private key content (ed25519 recommended)"
    BASTION_HOST       = aws_eip.bastion_eip.public_ip
    MANAGER_PRIVATE_IP = aws_instance.swarm_manager.private_ip
    ALB_DNS_NAME       = aws_lb.todo_alb.dns_name
  }
}

# Deployment URLs
output "deployment_endpoints" {
  description = "All deployment and monitoring endpoints"
  value = {
    main_app      = "http://${aws_lb.todo_alb.dns_name}"
    health_check  = "http://${aws_lb.todo_alb.dns_name}/health"
    api_docs      = "http://${aws_lb.todo_alb.dns_name}/swagger"
    direct_access = "http://${aws_instance.swarm_manager.public_ip}:8080"
  }
}


