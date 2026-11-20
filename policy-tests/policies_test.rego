# Local tests:  opa test ../policies . -v
package terraform.policies_test

import rego.v1

import data.terraform.policies.instance_type
import data.terraform.policies.mandatory_tags
import data.terraform.policies.no_public_ssh
import data.terraform.policies.vpc_cidr

good_tags := {"Project": "p", "Environment": "lab", "ManagedBy": "terraform", "Name": "x"}

plan(rcs) := {"plan": {"resource_changes": rcs}}

rc(type, after) := {
	"address": sprintf("%s.test", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after},
}

# ---------- instance type ----------
test_instance_t3_micro_passes if {
	count(instance_type.deny) == 0 with input as plan([rc("aws_instance", {"instance_type": "t3.micro", "tags_all": good_tags})])
}

test_instance_t3_large_denied if {
	count(instance_type.deny) == 1 with input as plan([rc("aws_instance", {"instance_type": "t3.large", "tags_all": good_tags})])
}

# ---------- tags ----------
test_tags_ok if {
	count(mandatory_tags.deny) == 0 with input as plan([rc("aws_vpc", {"cidr_block": "10.10.0.0/16", "tags_all": good_tags})])
}

test_tags_missing_denied if {
	count(mandatory_tags.deny) == 1 with input as plan([rc("aws_vpc", {"cidr_block": "10.10.0.0/16", "tags_all": {"Name": "x"}})])
}

test_untaggable_resource_ignored if {
	count(mandatory_tags.deny) == 0 with input as plan([rc("aws_route", {"destination_cidr_block": "0.0.0.0/0"})])
}

# ---------- SSH ----------
test_ssh_world_denied if {
	count(no_public_ssh.deny) == 1 with input as plan([rc(
		"aws_vpc_security_group_ingress_rule",
		{"cidr_ipv4": "0.0.0.0/0", "ip_protocol": "tcp", "from_port": 22, "to_port": 22},
	)])
}

test_ssh_my_ip_passes if {
	count(no_public_ssh.deny) == 0 with input as plan([rc(
		"aws_vpc_security_group_ingress_rule",
		{"cidr_ipv4": "203.0.113.10/32", "ip_protocol": "tcp", "from_port": 22, "to_port": 22},
	)])
}

test_all_traffic_world_denied if {
	count(no_public_ssh.deny) == 1 with input as plan([rc(
		"aws_vpc_security_group_ingress_rule",
		{"cidr_ipv4": "0.0.0.0/0", "ip_protocol": "-1", "from_port": null, "to_port": null},
	)])
}

test_http_world_passes if {
	count(no_public_ssh.deny) == 0 with input as plan([rc(
		"aws_vpc_security_group_ingress_rule",
		{"cidr_ipv4": "0.0.0.0/0", "ip_protocol": "tcp", "from_port": 80, "to_port": 80},
	)])
}

test_icmp_world_passes if {
	count(no_public_ssh.deny) == 0 with input as plan([rc(
		"aws_vpc_security_group_ingress_rule",
		{"cidr_ipv4": "0.0.0.0/0", "ip_protocol": "icmp", "from_port": -1, "to_port": -1},
	)])
}

test_inline_sg_ssh_denied if {
	count(no_public_ssh.deny) == 1 with input as plan([rc(
		"aws_security_group",
		{"ingress": [{"cidr_blocks": ["0.0.0.0/0"], "protocol": "tcp", "from_port": 22, "to_port": 22}]},
	)])
}

# ---------- VPC CIDR ----------
test_vpc_10_passes if {
	count(vpc_cidr.deny) == 0 with input as plan([rc("aws_vpc", {"cidr_block": "10.20.0.0/16"})])
}

test_vpc_172_flagged if {
	count(vpc_cidr.deny) == 1 with input as plan([rc("aws_vpc", {"cidr_block": "172.16.0.0/16"})])
}
