# Only small, cheap instance types are allowed in this lab.
package terraform.policies.instance_type

import rego.v1

allowed_types := {"t2.micro", "t3.micro"}

deny contains msg if {
	some rc in input.plan.resource_changes
	rc.type == "aws_instance"
	some action in rc.change.actions
	action in {"create", "update"}

	itype := rc.change.after.instance_type
	not itype in allowed_types

	msg := sprintf("%s uses instance_type %q. Allowed: %v", [rc.address, itype, allowed_types])
}
