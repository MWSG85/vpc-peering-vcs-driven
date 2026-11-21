# VPCs should use private RFC1918 address space (advisory = warning only).
package terraform.policies.vpc_cidr

import rego.v1

private_ranges := ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

is_private(cidr) if {
some range in private_ranges
net.cidr_contains(range, cidr)
}

deny contains msg if {
some rc in input.plan.resource_changes
rc.type == "aws_vpc"
some action in rc.change.actions
action in {"create", "update"}

cidr := rc.change.after.cidr_block
not is_private(cidr)

msg := sprintf("%s uses CIDR %s, which is not private RFC1918 space", [rc.address, cidr])
}
