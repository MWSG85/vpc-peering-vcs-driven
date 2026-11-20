variable "name" {
  type = string
}

variable "instance_type" {
  description = "Only t2.micro / t3.micro are allowed by OPA"
  type        = string
  default     = "t3.micro"
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_sg_id" {
  type = string
}

variable "private_sg_id" {
  type = string
}

variable "key_name" {
  description = "Existing EC2 key pair name (optional)"
  type        = string
  default     = null
}
