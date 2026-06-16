# Per-component gate for the monorepo.
#
# Evaluated by `kosli evaluate trail --assert` in the orchestrator's per-component
# `bind` job, against a single service's own flow (monorepo-web, monorepo-dashboard, ...).
# It is the load-bearing check: a component's bare artifact is attested into the
# shared co-deployment trail ONLY after this policy passes on its own flow. The
# co-deployment gate (policy/gate.rego) is presence-only and CANNOT re-derive a
# component's SDLC compliance, so the judgement must happen here, immediately
# before the bind.
#
# DESIGN (mirrors policy/gate.rego):
#   * Fail-safe default: deny unless positively proven compliant.
#   * Drive `allow` via a POSITIVE assertion, never via the absence of violations.
#     (A renamed/absent field then makes the rule not fire -> deny, not pass.)
#   * `violations` are diagnostics only and never feed into `allow`.
#
# WHY THE TRAIL-LEVEL FLAG IS ENOUGH: each service's trail template
# (source/<name>/kosli.yml) is scoped to exactly that service, so
# `input.trail.compliance_status.is_compliant` already means "this component's
# artifact, plus every trail-level attestation (e.g. pull-request), is present
# and compliant".
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
