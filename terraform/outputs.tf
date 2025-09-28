# App URLs
output "application_url" {
  description = "Main application URL"
  value       = "http://${aws_lb.todo_alb.dns_name}"
}

output "swagger_url" {
  description = "API documentation URL"
  value       = "http://${aws_lb.todo_alb.dns_name}/swagger"
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
  }
}


