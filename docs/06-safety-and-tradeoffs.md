# 6. Safety and trade-offs

This design is shaped throughout by the compliance asymmetry from
[doc 1](01-problem-and-goals.md): never report compliant when actually
non-compliant. This file collects the failure modes we designed against and the
deliberate choices that follow.

## Scope must come from an oracle, not from "what ran"

It is tempting to derive the expected set from which workflows actually fired.
That is the fail-open direction. A component that *should* have built but did not
(a bad path glob, a YAML error, a runner outage, a cancelled run) would simply be
absent from the "fired" set, the binding template would omit it, and the trail
would go green. That is a false-compliant.

So the scope comes from an independent oracle: the path-filter diff in the
always-on `scope` job. That job runs on every commit precisely so it can observe a
component's silence. Only something that always runs can police what failed to
run.

## How the gate tells "B ran but failed" from "C did not run"

It does not look at the per-service flows to decide this, and it must not. The
distinction lives in the binding template plus the assert-then-attest ordering:

- C is **not in the binding template** (C unchanged), so the gate never asks about
  C.
- B **is in the binding template**. B is compliant in the binding trail only if
  its artifact is present, and B's artifact is present only if B passed its own
  gate and reached its binding attestation. If B failed its gate it never attests,
  so B is `MISSING` in the binding trail and the gate denies. If B never ran at
  all, same outcome.

"B ran but failed" and "B never reported" both leave B `MISSING` in the binding
trail, which is the correct outcome for anything in scope. The gate needs no way
to tell them apart.

## The trust boundary: assert before attest

The binding gate does not re-verify each service's evidence. It trusts that a
service writes its artifact into the binding trail only after passing its own gate.
That invariant is the assert-then-attest step ordering in each component workflow
(`kosli assert artifact`, then `kosli attest artifact --flow
monorepo-co-deployment`). A failed assert exits non-zero and stops the job before
the binding attestation.

This is the one place a false-compliant could be introduced: a workflow that
attested to the binding trail *before*, or *regardless of*, its own gate would
contribute an ungated artifact. So that ordering is a load-bearing invariant, not
a stylistic choice. Anything that reorders or unguards the binding attestation
breaks the asymmetry. A useful future safeguard would be a CI check that the
binding attestation step always follows the self-check in every component
workflow.

## Bias the scope toward over-inclusion

If the scope computation is ever unsure whether a component changed, it should
include it. Over-inclusion makes the gate stricter (one more artifact that must be
present and gated), which is the safe direction. Under-inclusion is the one error
that can leak a false-compliant, so path globs should err broad (e.g. include a
component's own workflow file in its filter).

## Trust the binding trail's aggregate flag, not a single artifact's flag

The gate asserts the **trail-level** `is_compliant` of the binding trail because
it is the complete aggregate over every in-scope artifact. A single artifact's
flag does not represent the whole commit. The gate also does not, and cannot, read
any per-service flow's compliance: `kosli evaluate trail` judges one trail, which
is exactly why the binding flow exists as the single place every service's
post-gate verdict is collected.

## Fail-closed behaviours, collected

- `gate` runs under `!cancelled()`, so a skipped or failed component cannot
  silently skip the gate. (CI-orchestration behaviour; not covered by the CLI
  system tests, see Coverage gaps below.)
- The Rego defaults to deny and proves compliance positively, so a renamed/absent
  field denies rather than passes. (Source-level argument only; not system-tested,
  since proving it needs a fabricated policy input, which the tests forbid.)
- A failed self-check in a component's own flow stops the job before its binding
  attestation, so the component stays `MISSING` in the binding trail.
- A naming drift between a fragment and its workflow surfaces as `MISSING` and
  fails closed: inside the service's own flow it trips that service's gate; on the
  artifact name it leaves the binding artifact `MISSING`.
- A missing expected artifact in the binding trail is explicit (`MISSING`) and
  makes the binding trail non-compliant.

## Kosli behaviours relied on (verified against a fresh server)

These are server-behaviour facts, established by driving a fresh local server with
the real CLI, that the design depends on regardless of topology:

1. An expected-but-unreported artifact is NOT omitted from `artifacts_statuses`;
   it is listed with `status: "MISSING"` and the trail is non-compliant.
2. A missing expected attestation renders a trail non-compliant.
3. An unexpected (not-in-template) attestation that is non-compliant still makes
   the trail non-compliant; "unexpected" means "not required", not "ignored".

## Coverage gaps and pending rework

- **The `test/*.sh` suite predates the two-tier rework.** It proves the
  Kosli-behaviour facts above and the *old* single-shared-flow tie-together. It
  does not yet exercise per-service flows, the assert-then-attest ordering, or the
  binding-trail gate. It needs reworking before it again end-to-end proves this
  design. See [findings](findings.md).
- CI orchestration (doc 3): `needs`, `if: !cancelled()`, conditional dispatch, the
  always-on scope job, scope-from-an-oracle, over-inclusion, and the
  assert-before-attest ordering are GitHub Actions semantics and would need an
  Actions-level harness (e.g. `act`).
- The Rego "renamed/absent field -> deny" fail-safe is only demonstrable with a
  fabricated policy input, which our tests forbid, so it stays a source-level
  argument (the policy's `== true` structure).
