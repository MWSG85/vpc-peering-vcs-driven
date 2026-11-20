variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "admin_cidr" {
  description = "Your public IP in /32 form, allowed to SSH to the bastion. 0.0.0.0/0 is blocked by OPA."
  type        = string
}
