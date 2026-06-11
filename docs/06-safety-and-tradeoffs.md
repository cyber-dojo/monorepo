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

The gate asserts the **trail-level** `is_compliant` because it is the complete
aggregate -- it covers every trail-level attestation plus every artifact. A
single artifact's flag does not represent the whole commit, and the
artifact<->trail-level relationship is attestation-dependent: on the current
server a missing trail-level attestation drags the artifact non-compliant
(`test/test_artifact_compliance_when_trail_attestation_missing.sh`), whereas
older production trails behaved inconsistently (see [findings](findings.md)).
Gating on the aggregate sidesteps that entirely.

## Fail-closed behaviours, collected

- `gate` runs under `!cancelled()`, so a skipped or failed component cannot
  silently skip the gate. (CI-orchestration behaviour; not covered by the CLI
  system tests -- see Coverage gaps below.)
- The Rego defaults to deny and proves compliance positively, so a renamed/absent
  field denies rather than passes. (Source-level argument only; not system-tested,
  since proving it needs a fabricated policy input, which the tests forbid.)
- A naming drift between a fragment and its workflow surfaces as MISSING ->
  non-compliant -- the same mechanism as a missing attestation
  (`test/test_missing_artifact_attestation.sh`).
- A missing expected attestation is explicit (`MISSING`) and makes the trail
  non-compliant. Proved: `test/test_missing_artifact_attestation.sh`,
  `test/test_in_scope_artifact_never_reported.sh`,
  `test/test_artifact_compliance_when_trail_attestation_missing.sh`.

## Resolved against a fresh server

1. An expected-but-unreported artifact is NOT omitted from `artifacts_statuses`;
   it is listed with `status: "MISSING"` and the trail is non-compliant. Proved:
   `test/test_in_scope_artifact_never_reported.sh`.
2. A missing expected attestation renders the trail non-compliant. Proved:
   `test/test_missing_artifact_attestation.sh`,
   `test/test_artifact_compliance_when_trail_attestation_missing.sh`.

## Coverage gaps (not exercised by the CLI system tests)

- CI orchestration (doc 3): `needs`, `if: !cancelled()`, conditional dispatch,
  the always-on scope job, scope-from-an-oracle, over-inclusion. These are GitHub
  Actions semantics and would need an Actions-level harness (e.g. `act`).
- The Rego "renamed/absent field -> deny" fail-safe: only demonstrable with a
  fabricated policy input, which our tests forbid, so it stays a source-level
  argument (the policy's `== true` structure).
