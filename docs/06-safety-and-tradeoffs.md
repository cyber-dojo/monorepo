# 6. Safety and trade-offs

This design is shaped throughout by the compliance asymmetry from
[doc 1](01-problem-and-goals.md): never report compliant when actually
non-compliant. This file collects the failure modes we designed against and the
deliberate choices that follow.

## Scope must come from an oracle, not from "what ran"

It is tempting to derive the expected set from which workflows actually fired.
That is the fail-open direction. A component that *should* have built but did not
-- a bad path glob, a YAML error, a runner outage, a cancelled run -- would
simply be absent from the "fired" set, the scoped template would omit it, and the
trail would go green. That is a false-compliant.

So the scope comes from an independent oracle: the path-filter diff in the
always-on `scope` job. That job runs on every commit precisely so it can observe a
component's silence. Only something that always runs can police what failed to
run.

## How the gate tells "B ran but is non-compliant" from "C did not run"

It does not look at the trail to decide this, and it must not. The distinction
lives entirely in the scope:

- C is **not in the scoped template**, so the gate never asks about C.
- B **is in the scoped template**. The trail-level flag is true only if B is
  present and compliant. If B is missing an attestation it shows as MISSING ->
  trail not compliant -> deny. If B never reported at all, same outcome.

"B ran but failed" and "B never reported" both fail the same positive check,
which is the correct outcome for anything in scope. The gate needs no way to tell
them apart.

## Bias the scope toward over-inclusion

If the scope computation is ever unsure whether a component changed, it should
include it. Over-inclusion makes the gate stricter (more to prove) -- the safe
direction. Under-inclusion is the one error that can leak a false-compliant, so
path globs should err broad (e.g. include a component's own workflow file in its
filter).

## Trust the trail-level flag, not a single artifact's flag

Verified on real data: a trail is never compliant while an artifact is
non-compliant, but an artifact can be green while the trail is red (a missing
trail-level attestation). So the gate asserts the **trail-level**
`is_compliant`, which is the complete aggregate. A per-artifact check alone could
miss a missing trail-level attestation.

## Fail-closed behaviours, collected

- `gate` runs under `!cancelled()`, so a skipped or failed component cannot
  silently skip the gate.
- The Rego defaults to deny and proves compliance positively, so a renamed/absent
  field denies rather than passes.
- A naming drift between a fragment and its workflow surfaces as MISSING ->
  non-compliant.
- A missing expected attestation is explicit (`MISSING`) and makes the trail
  non-compliant.

## Open questions to confirm in your environment

The design rests on behaviours we verified against cyber-dojo's real trails, but
two are worth re-confirming on your own instance before relying on them:

1. That `artifacts_statuses` omits expected-but-unreported artifacts (so absence
   is what scoping, not the trail, must account for).
2. That a missing expected attestation always renders the trail `is_compliant:
   false` (it did in every one of the 215 compliant trails we checked).

Both are directly observable with `kosli evaluate trail --show-input --output
json` (see [doc 5](05-the-gate-policy.md)). The asymmetry rule says: until
confirmed, prefer the stricter interpretation.
