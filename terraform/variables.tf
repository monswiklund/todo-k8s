variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "admin_ip_cidr" {
  description = "CIDR block for admin SSH access"
  type        = string
  default     = "83.252.50.4/32"  
}
