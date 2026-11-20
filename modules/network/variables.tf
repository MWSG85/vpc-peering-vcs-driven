variable "name" {
  description = "Name prefix, e.g. frontend or backend"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (must be inside 10.0.0.0/8 — OPA policy)"
  type        = string
}

variable "az_count" {
  description = "How many AZs / subnet pairs to create"
  type        = number
  default     = 3
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway for private subnets (costs money per hour)"
  type        = bool
  default     = true
}
