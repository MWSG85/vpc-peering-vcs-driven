# VPCs should use private 10.0.0.0/8 address space (advisory = warning only).
package terraform.policies.vpc_cidr

import rego.v1

deny contains msg if {
	some rc in input.plan.resource_changes
	rc.type == "aws_vpc"
	some action in rc.change.actions
	action in {"create", "update"}

	cidr := rc.change.after.cidr_block
	not net.cidr_contains("10.0.0.0/8", cidr)

	msg := sprintf("%s uses CIDR %s, which is outside 10.0.0.0/8", [rc.address, cidr])
}
