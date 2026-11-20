terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# No access keys here. HCP Terraform injects short-lived AWS credentials
# through OIDC (TFC_AWS_PROVIDER_AUTH + TFC_AWS_RUN_ROLE_ARN in the
# project variable set created by workspace-runner).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Tier        = "backend"
    }
  }
}
