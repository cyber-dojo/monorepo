# 5. The gate policy

`policy/gate.rego` is evaluated by `kosli evaluate trail` in the `gate` job,
against the `monorepo-co-deployment` trail. It turns that one binding trail into a
single allow/deny verdict for the whole commit.

Its sibling `policy/component.rego` is the per-service gate, evaluated by each
`bind-<X>` job against that service's own flow (`monorepo-a`, ...) before the
service is recorded in the binding trail. The two policies are structurally
identical -- both default-deny and assert the trail's `is_compliant` flag is
exactly `true` -- and differ only in which trail they judge. Everything below
about `gate.rego`'s rules applies equally to `component.rego`.

## The policy

```rego
package policy
import rego.v1

default allow := false

allow if {
	input.trail.compliance_status.is_compliant == true
}

violations contains msg if { ... }   # diagnostics only
```

## Three rules it obeys (Kosli's documented guidance)

1. **Fail-safe default.** `default allow := false`. Anything the policy cannot
   positively verify is treated as non-compliant.
2. **Drive `allow` by positive assertion, never by the absence of violations.**
   The unsafe pattern is `allow if count(violations) == 0`: if a field is renamed
   or the schema changes, the violations set is empty for the wrong reason and the
   policy grants a false-positive compliant. Our `allow` instead requires the
   `is_compliant` field to be present and exactly `true`; if it is absent or
   renamed the expression is undefined, the rule does not fire, and we deny.
3. **Violations are diagnostics only.** They explain a denial in the output; they
   never feed into `allow`. (The policy also has a trail-level-attestation
   diagnostics rule. The binding trail carries no trail-level attestations, so that
   rule simply never fires here; it is harmless and left in place.)

## Why one assertion on the binding trail's flag is enough

The whole-commit guarantee rests on two facts that compose:

1. **The binding template is scoped per commit** (see
   [doc 4](04-template-fragments.md)), so
   `input.trail.compliance_status.is_compliant` for the `monorepo-co-deployment`
   trail means "every artifact this commit should have built is present in the
   binding trail". A commit that built only A and B expects only A and B; a
   skipped C is not asked about.
2. **The orchestrator binds an artifact into the binding trail only after the
   service passes its own gate** (the evaluate-then-bind ordering in the `bind-<X>`
   job, see [doc 3](03-ci-orchestration.md)). So an artifact being present in the
   binding trail is not just "it built"; it is "it built and cleared its own SDLC
   controls". The detailed evidence (lint, unit-test, pull-request) lives in that
   service's own flow; the binding trail records the post-gate verdict as the
   artifact's presence.

Together: the binding flag is `true` exactly when every in-scope service built and
passed its own controls. A service that was in scope but failed, or never ran,
leaves its expected artifact `MISSING` in the binding trail, so the flag is `false`
and the gate denies. Fail-closed.

The trust boundary is the evaluate-then-bind ordering. The whole-commit gate does
not re-verify each service's evidence; it relies on the bind job never attesting
to the binding trail ahead of the service's own gate. A failed `kosli evaluate
trail --flow monorepo-a --policy component.rego --assert` exits non-zero and (under
`set -euo pipefail`) stops the bind job before the binding attestation, so the
only way to leak a false-compliant (binding an ungated artifact) cannot occur
through the workflow as written.

## Field shapes (confirmed against real data)

```
input.trail.compliance_status
  .is_compliant            bool
  .status                  "COMPLIANT" | "INCOMPLETE" | "NON-COMPLIANT" | ...
  .attestations_statuses   [ {attestation_name, status, is_compliant, unexpected}, ... ]   # trail-level
  .artifacts_statuses      { "<name>": { status, is_compliant, artifact_fingerprint,
                                          attestations_statuses: [ ... ] }, ... }
```

Note `attestations_statuses` is an **array** (empty for the binding trail);
`artifacts_statuses` is a **map** keyed by artifact name. The binding gate's
verdict turns entirely on the `artifacts_statuses` entries being present and
compliant.

## Inspect the real input before trusting field paths

```
kosli evaluate trail <SHA> \
  --flow monorepo-co-deployment --org cyber-dojo --policy policy/gate.rego \
  --show-input --output json \
  | jq '.trail.compliance_status | {is_compliant, status, artifacts_statuses, attestations_statuses}'
```

Run this against a known compliant binding trail and a known non-compliant one
before relying on the policy in anger. (Confirm the exact flag spelling with
`kosli evaluate trail --help`.)

## Status of the proving tests

The `test/*.sh` suite exercises both policies against a fresh local server: the
per-service gate (`component.rego` over each `monorepo-<x>` flow) in the Tier-1
`test_service_gate_*` tests, and the whole-commit gate (`gate.rego` over the
binding trail) in the Tier-2 `test_binding_gate_*` tests. The Tier-3
`test_failed_service_gate_keeps_artifact_out_of_binding.sh` proves the
evaluate-then-bind boundary end to end. The suite needs a local Kosli server to
run (`test/run.sh`); see [findings](findings.md).

## If you cannot scope the binding template per commit

Then the binding flag would be false whenever a component legitimately did not
build, so you could not gate on it. The fallback is a params-scoped policy: pass
the expected set in (`--params '{"expected":["A","B"]}'`) and positively prove
each expected artifact is present and compliant. It works but is strictly more
complex, which is why template scoping is the recommended path.
