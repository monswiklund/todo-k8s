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

# CI/CD Information
output "cicd_setup" {
  description = "GitHub Actions secrets needed for CI/CD"
  value = {
    required_secrets = [
      "DOCKER_USERNAME - Docker Hub username",
      "DOCKER_PASSWORD - Docker Hub password or access token",
      "AWS_ACCESS_KEY_ID - AWS IAM user access key with SSM permissions",
      "AWS_SECRET_ACCESS_KEY - AWS IAM user secret key",
      "SWARM_MANAGER_INSTANCE_ID - Manager EC2 instance ID"
    ]
    swarm_manager_instance_id = aws_instance.swarm_manager.id
    swarm_manager_ip          = aws_instance.swarm_manager.public_ip
    deploy_method             = "AWS SSM Session Manager (secure, no SSH ports)"
    deploy_command            = "Automated via GitHub Actions on push to master"
  }
}

# Monitoring Information
output "monitoring_setup" {
  description = "CloudWatch Logs and Monitoring Information"
  value = {
    cloudwatch_log_groups = [
      aws_cloudwatch_log_group.todoapp_application.name,
      aws_cloudwatch_log_group.todoapp_docker.name
    ]
    sns_topic_arn = aws_sns_topic.todoapp_alerts.arn
    alarms = [
      aws_cloudwatch_metric_alarm.high_error_rate.alarm_name,
      aws_cloudwatch_metric_alarm.high_response_time.alarm_name,
      aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name
    ]
    log_retention_days = {
      application = aws_cloudwatch_log_group.todoapp_application.retention_in_days
      docker      = aws_cloudwatch_log_group.todoapp_docker.retention_in_days
    }
  }
}