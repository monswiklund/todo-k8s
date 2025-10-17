########################################
# MAIN ENTRYPOINT
########################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data
data "aws_availability_zones" "available" {}
