# Basic test policy: cap how long an environment may run.
#
# Type: torque.environment, evaluated on every launch and extend.
#
# Data (set in Torque when the policy is applied to a space):
#   max_duration_minutes  number  Longest total lifetime allowed, e.g. 240 (4 hours)
#
# Behaviour:
#   Launch  the requested duration must be <= max_duration_minutes
#   Extend  the duration so far plus the extension must be <= max_duration_minutes
#   Environments with no end time ("always on") are denied.
package torque.environment

import future.keywords.if

# On launch, duration_minutes is the requested duration. On extend, it is
# the total duration before the extension, so the extension is added on.
total_minutes := input.duration_minutes if {
	input.action_identifier.action_type == "Launch"
}

total_minutes := input.duration_minutes + input.extend_duration_minutes if {
	input.action_identifier.action_type == "Extend"
}

no_end_time if not is_number(input.duration_minutes)

too_long if total_minutes > data.max_duration_minutes

result := {
	"decision": "Denied",
	"reason": "Environments must have an end time; open-ended environments are not allowed in this space",
} if {
	no_end_time
}

result := {"decision": "Denied", "reason": reason} if {
	not no_end_time
	too_long
	reason := sprintf(
		"%v of %v minutes exceeds the %v-minute limit for this space",
		[lower(input.action_identifier.action_type), total_minutes, data.max_duration_minutes],
	)
}

result := {"decision": "Approved"} if {
	not no_end_time
	not too_long
}
