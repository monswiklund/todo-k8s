output "cluster_name"     { value = aws_eks_cluster.this.name }
output "cluster_endpoint" { value = aws_eks_cluster.this.endpoint }
output "cluster_ca"       { value = aws_eks_cluster.this.certificate_authority[0].data }
output "vpc_id"           { value = aws_vpc.main.id }
output "public_subnets"   { value = aws_subnet.public_subnet[*].id }
output "private_subnets"  { value = aws_subnet.private_subnet[*].id }