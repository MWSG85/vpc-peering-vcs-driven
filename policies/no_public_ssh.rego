# Block SSH (port 22) open to the whole internet (0.0.0.0/0).
package terraform.policies.no_public_ssh

import rego.v1

# Style 1: separate rule resources (what this repo uses)
deny contains msg if {
	some rc in input.plan.resource_changes
	rc.type == "aws_vpc_security_group_ingress_rule"
	some action in rc.change.actions
	action in {"create", "update"}

	rule := rc.change.after
	rule.cidr_ipv4 == "0.0.0.0/0"
	covers_ssh(rule.ip_protocol, rule.from_port, rule.to_port)

	msg := sprintf("%s opens SSH (22) to 0.0.0.0/0. Use your own IP /32.", [rc.address])
}

# Style 2: inline ingress blocks inside aws_security_group
deny contains msg if {
	some rc in input.plan.resource_changes
	rc.type == "aws_security_group"
	some action in rc.change.actions
	action in {"create", "update"}

	some ing in rc.change.after.ingress
	"0.0.0.0/0" in ing.cidr_blocks
	covers_ssh(ing.protocol, ing.from_port, ing.to_port)

	msg := sprintf("%s has an inline rule opening SSH (22) to 0.0.0.0/0.", [rc.address])
}

# "-1" = all protocols / all ports
covers_ssh(protocol, _, _) if protocol == "-1"

covers_ssh(protocol, from, to) if {
	protocol in {"tcp", "6"}
	from <= 22
	to >= 22
}
