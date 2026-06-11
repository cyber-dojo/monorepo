# 5. The gate policy

`policy/gate.rego` is evaluated by `kosli evaluate trail` in the `gate` job. It
turns the whole scoped trail into one allow/deny verdict.

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
   never feed into `allow`.

## Why one assertion on the trail-level flag is enough

Because the template is scoped per commit (see [doc 4](04-template-fragments.md)),
`input.trail.compliance_status.is_compliant` already means: "every artifact this
commit should have built, plus every trail-level attestation, is present and
compliant". The suite proves the flag behaves that way against a fresh server:

- it is `true` only when everything required is present and compliant
  (`test/test_green_path_all_compliant.sh`,
  `test/test_two_components_all_compliant.sh`), and
- it is `false` when any in-scope attestation or artifact is missing or
  non-compliant (`test/test_missing_artifact_attestation.sh`,
  `test/test_in_scope_artifact_never_reported.sh`,
  `test/test_failing_attestation.sh`,
  `test/test_two_components_one_not_compliant.sh`).

A MISSING expected attestation is represented explicitly (`status: "MISSING"`)
and drags the trail to not-compliant, so a component that was in scope but failed
to attest cannot slip through.

## Field shapes (confirmed against real data)

```
input.trail.compliance_status
  .is_compliant            bool
  .status                  "COMPLIANT" | "INCOMPLETE" | "NON-COMPLIANT" | ...
  .attestations_statuses   [ {attestation_name, status, is_compliant, unexpected}, ... ]   # trail-level
  .artifacts_statuses      { "<name>": { status, is_compliant, artifact_fingerprint,
                                          attestations_statuses: [ ... ] }, ... }
```

Note `attestations_statuses` is an **array**; `artifacts_statuses` is a **map**
keyed by artifact name.

## Inspect the real input before trusting field paths

```
kosli evaluate trail <TRAIL> \
  --flow <FLOW> --org cyber-dojo --policy policy/gate.rego \
  --show-input --output json \
  | jq '.trail.compliance_status | {is_compliant, status, artifacts_statuses, attestations_statuses}'
```

Run this against a known compliant trail and a known non-compliant one before
relying on the policy in anger. (Confirm the exact flag spelling with
`kosli evaluate trail --help`.)

## If you cannot scope the template per commit

Then the trail-level flag would be false whenever a component legitimately did not
build, so you could not gate on it. The fallback is a params-scoped policy:
pass the expected set in (`--params '{"expected":["A","B"]}'`) and positively
prove each expected artifact is present and compliant, plus a separate positive
check of the trail-level attestations array. It works but is strictly more
complex, which is why template scoping is the recommended path.
