# Run this ONCE from your laptop with your own AWS credentials (aws configure).
# It creates the trust between HCP Terraform and AWS:
#   HCP Terraform run --(OIDC token)--> AWS STS --> temporary creds for this IAM role
# After this, no AWS access keys are stored anywhere in HCP Terraform.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  tfc_hostname = "app.terraform.io"
  audience     = "aws.workload.identity"
}

# ---------- OIDC identity provider ----------
data "tls_certificate" "tfc" {
  url = "https://${local.tfc_hostname}"
}

resource "aws_iam_openid_connect_provider" "tfc" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://${local.tfc_hostname}"
  client_id_list  = [local.audience]
  thumbprint_list = [data.tls_certificate.tfc.certificates[0].sha1_fingerprint]
}

# If you already created this provider in an earlier lab, set
# create_oidc_provider = false and it will be looked up instead.
data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.tfc_hostname}"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.tfc[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
}

# ---------- IAM role that HCP Terraform runs will assume ----------
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.tfc_hostname}:aud"
      values   = [local.audience]
    }

    # Only runs from workspaces inside THIS org + project can assume the role
    condition {
      test     = "StringLike"
      variable = "${local.tfc_hostname}:sub"
      values   = ["organization:${var.tfc_organization}:project:${var.tfc_project_name}:workspace:*:run_phase:*"]
    }
  }
}

resource "aws_iam_role" "tfc" {
  name                 = "tfc-${var.tfc_project_name}-role"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

# Lab permissions: EC2 full access also covers VPC, subnets, SGs, peering.
resource "aws_iam_role_policy_attachment" "ec2" {
  role       = aws_iam_role.tfc.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

output "role_arn" {
  description = "Paste this into workspace-runner variable aws_role_arn"
  value       = aws_iam_role.tfc.arn
}
