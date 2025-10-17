variable "region" { 
  type = string  
  default = "eu-west-1" 
}
variable "cluster_name" { 
  type = string  
  default = "k8s-eks" 
}

variable "vpc_cidr" { 
  type = string  
  default = "10.0.0.0/16" 
}
variable "instance_type" { 
  type = string  
  default = "t3.small" 
}
variable "desired_size" { 
  type = number  
  default = 2 
}
variable "min_size" { 
  type = number  
  default = 2
}
variable "max_size" {
  type = number
  default = 4
}