# HCP Terraform reads this file to know which OPA rules to evaluate.
# query  = the Rego rule to run (each returns a set of violation messages)
# enforcement_level:
#   mandatory = a violation BLOCKS the apply
#   advisory  = a violation only shows a warning

policy "mandatory_tags" {
  query             = "data.terraform.policies.mandatory_tags.deny"
  enforcement_level = "mandatory"
}

policy "allowed_instance_types" {
  query             = "data.terraform.policies.instance_type.deny"
  enforcement_level = "mandatory"
}

policy "no_public_ssh" {
  query             = "data.terraform.policies.no_public_ssh.deny"
  enforcement_level = "mandatory"
}

policy "vpc_cidr_range" {
  query             = "data.terraform.policies.vpc_cidr.deny"
  enforcement_level = "advisory"
}
