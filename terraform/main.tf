########################################
# MAIN ENTRYPOINT
# The Terraform configuration has been left in place for reference,
# but the actual infrastructure resources are commented out because
# the course deployment uses EKS Auto Mode (created via AWS Console).
# You can uncomment the files in this module if you want to provision
# a traditional EKS cluster with managed node groups using Terraform.
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
