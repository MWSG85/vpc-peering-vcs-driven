variable "tfc_organization" {
  description = "HCP Terraform organization name"
  type        = string
}

variable "project_name" {
  description = "Project that holds the 7 workspaces. Must match the OIDC trust (tfc_project_name)."
  type        = string
  default     = "vpc-peering-vcs-driven"
}

variable "github_repo" {
  description = "GitHub repo as owner/name, e.g. myowin/vpc-peering-vcs-driven"
  type        = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "oauth_token_id" {
  description = "OAuth token ID of the GitHub VCS provider (ot-xxxxxxxx). Org Settings > Version Control > Providers."
  type        = string
}

variable "aws_role_arn" {
  description = "role_arn output from 00-bootstrap-aws-oidc"
  type        = string
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  type    = string
  default = "lab"
}

variable "admin_cidr" {
  description = "Your public IP as x.x.x.x/32 for SSH to the bastions"
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair name in the region (for SSH testing)"
  type        = string
  default     = ""
}

variable "auto_apply" {
  description = "Apply automatically after a successful plan + policy check"
  type        = bool
  default     = true
}
