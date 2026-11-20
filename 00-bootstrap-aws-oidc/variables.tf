variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "tfc_organization" {
  description = "Your HCP Terraform organization name"
  type        = string
}

variable "tfc_project_name" {
  description = "Must match project_name in workspace-runner"
  type        = string
  default     = "vpc-peering-vcs-driven"
}

variable "create_oidc_provider" {
  description = "false if an app.terraform.io OIDC provider already exists in this AWS account"
  type        = bool
  default     = true
}
