output "swarm_manager_ip" {
  description = "Public IP of swarm manager"
  value       = aws_instance.swarm_manager.public_ip
}

output "swarm_worker_ips" {
  description = "Public IPs of swarm workers"
  value       = aws_instance.swarm_workers[*].public_ip
}

output "ssh_command" {
  description = "SSH command to connect to manager"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.swarm_manager.public_ip}"
}