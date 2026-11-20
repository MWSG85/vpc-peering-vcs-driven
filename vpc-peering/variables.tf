# ---- Shared variables (values come from the project variable set) ----
variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "tfc_organization" {
  description = "HCP Terraform organization name (used to read other workspaces' state)"
  type        = string
}

variable "project" {
  type    = string
  default = "vpc-peering-vcs-driven"
}

variable "environment" {
  type    = string
  default = "lab"
}

variable "app_port" {
  description = "App port the backend opens to the frontend"
  type        = number
  default     = 8080
}
