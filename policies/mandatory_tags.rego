# Every resource that supports tags must carry Project, Environment and ManagedBy.
# We check tags_all (= resource tags + provider default_tags).
package terraform.policies.mandatory_tags

import rego.v1

required_tags := {"Project", "Environment", "ManagedBy"}

deny contains msg if {
	some rc in input.plan.resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}

	tags := object.get(rc.change.after, "tags_all", null)
	is_object(tags)

	present := {k | some k, _ in tags}
	missing := required_tags - present
	count(missing) > 0

	msg := sprintf("%s is missing required tags: %v", [rc.address, missing])
}
