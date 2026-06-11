# Whole-commit compliance gate for the monorepo.
#
# Evaluated by `kosli evaluate trail` in the orchestrator's `gate` job. It ties
# the compliance of every component built on this commit together into one
# allow/deny verdict.
#
# DESIGN (see docs/05-the-gate-policy.md):
#   * Fail-safe default: deny unless positively proven compliant.
#   * Drive `allow` via a POSITIVE assertion, never via the absence of violations.
#     (A renamed/absent field then makes the rule not fire -> deny, not pass.)
#   * `violations` are diagnostics only and never feed into `allow`.
#
# WHY THE TRAIL-LEVEL FLAG IS ENOUGH: the trail's template is scoped per commit
# (bin/scoped-template), so `input.trail.compliance_status.is_compliant` already
# means "every artifact this commit should have built, plus every trail-level
# attestation, is present and compliant". Verified on 276 real cyber-dojo trails:
# this flag was never true while any expected attestation was MISSING or any
# reported artifact was non-compliant.
#
# The package MUST be `policy` and define an `allow` rule -- this is what the
# `kosli evaluate` CLI requires.
package policy

import rego.v1

default allow := false

# The single positive assertion. If the field is missing or renamed, this is
# undefined, the rule does not fire, and `allow` stays false.
allow if {
	input.trail.compliance_status.is_compliant == true
}

# ---- diagnostics only: explain a denial; never referenced by `allow` ----

violations contains msg if {
	some name, artifact in input.trail.compliance_status.artifacts_statuses
	artifact.is_compliant != true
	msg := sprintf("artifact %q is %v", [name, artifact.status])
}

violations contains msg if {
	some att in input.trail.compliance_status.attestations_statuses
	att.unexpected == false
	att.is_compliant != true
	msg := sprintf("trail attestation %q is %v", [att.attestation_name, att.status])
}
