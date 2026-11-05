# Unit tests for max_duration.rego. Run from the repo root:
#   opa test policies/ -v
package torque.environment.max_duration_test

import future.keywords.if

import data.torque.environment

launch(minutes) := {
	"duration_minutes": minutes,
	"extend_duration_minutes": null,
	"action_identifier": {"entity_type": "Environment", "entity_id": null, "action_type": "Launch"},
}

extend(minutes, extra) := {
	"duration_minutes": minutes,
	"extend_duration_minutes": extra,
	"action_identifier": {"entity_type": "Environment", "entity_id": "abc123", "action_type": "Extend"},
}

test_launch_under_limit_approved if {
	environment.result.decision == "Approved" with input as launch(120) with data.max_duration_minutes as 240
}

test_launch_at_limit_approved if {
	environment.result.decision == "Approved" with input as launch(240) with data.max_duration_minutes as 240
}

test_launch_over_limit_denied if {
	r := environment.result with input as launch(480) with data.max_duration_minutes as 240
	r.decision == "Denied"
	r.reason == "launch of 480 minutes exceeds the 240-minute limit for this space"
}

test_extend_within_limit_approved if {
	environment.result.decision == "Approved" with input as extend(120, 60) with data.max_duration_minutes as 240
}

test_extend_past_limit_denied if {
	r := environment.result with input as extend(200, 60) with data.max_duration_minutes as 240
	r.decision == "Denied"
	r.reason == "extend of 260 minutes exceeds the 240-minute limit for this space"
}

test_no_end_time_denied if {
	environment.result.decision == "Denied" with input as launch(null) with data.max_duration_minutes as 240
}

test_mock_input_approved if {
	environment.result.decision == "Approved" with input as data.mock with data.max_duration_minutes as 240
}
