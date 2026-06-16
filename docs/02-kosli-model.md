# 2. The Kosli model we rely on

A short tour of the Kosli concepts this design depends on. (Reference:
https://docs.kosli.com/)

## Flow, trail, artifact, attestation

- A **flow** models a process. Here we use one flow per service for that
  service's build (`monorepo-web`, `monorepo-dashboard`, `monorepo-creator`), plus one extra flow
  (`monorepo-co-deployment`) that binds a commit's services together.
- A **trail** is one execution of a flow. We key every trail on the commit SHA,
  so each service's build trail and the co-deployment trail for the same commit
  all share the name `${github.sha}`.
- An **artifact** is a thing you built (a binary, image, tarball), identified by
  its SHA256 fingerprint, or before it exists by its template name plus the
  commit.
- An **attestation** is a piece of evidence (a test result, a scan, a PR).

## Two tiers of flow (the key structure)

The design splits one logical "build the monorepo" process across two tiers of
flow, because `kosli evaluate trail` judges a single trail and cannot read
another flow's compliance.

**Per-service build flows.** Each service has its own flow and its own template
(`source/<X>/kosli.yml`). On a commit that touches service A, A's reusable
workflow opens a trail in `monorepo-web` and reports A's full SDLC evidence there:
a trail-level `pull-request`, the artifact `A`, and the artifact's attestations
(`A.lint`, `A.unit-test`). A's workflow does not gate itself; it returns its flow
name, and the orchestrator applies A's gate later by evaluating this flow's trail
(`kosli evaluate trail --flow monorepo-web --policy component.rego`, see
[doc 3](03-ci-orchestration.md)). So everything that proves A is well-built lives
in A's flow.

**The co-deployment binding flow.** A separate flow, `monorepo-co-deployment`,
records only the co-deployment set: which services were built on this commit and
cleared their own gate. Its per-commit template lists one bare artifact per
in-scope component, with no attestations. The orchestrator's bind job attests a
service's artifact into this trail (`kosli attest artifact --fingerprint <sha>
--name A --flow monorepo-co-deployment --trail <sha>`) only after that service
passes its own gate, so the presence of the artifact is the evidence. The
whole-commit gate ([doc 5](05-the-gate-policy.md)) evaluates this one trail.

The binding flow holds presence; the per-service flows hold the evidence. This
works only because the orchestrator pushes each service's post-gate verdict (the
artifact attestation) into the binding trail. The binding gate never reads the
per-service flows.

## Per-trail template scoping (the key lever for the binding flow)

A flow has a default template, but `kosli begin trail --template-file` lets each
trail override it. We exploit this on the binding flow: the `scope` job composes a
template containing only the components that changed, and opens the
co-deployment trail with it. That trail's notion of "complete and compliant" is
therefore scoped to exactly this commit (a commit that legitimately built only A
and B expects only A and B).

## What "trail is compliant" actually means

These are facts about the Kosli server's compliance flag, established by driving a
fresh local server with the real CLI:

- The compliance status is exposed at `input.trail.compliance_status` with
  `is_compliant`, `status`, a trail-level `attestations_statuses` array, and an
  `artifacts_statuses` map keyed by artifact name (each artifact has its own
  `is_compliant`, `status`, and an `attestations_statuses` array).
- A **missing** expected attestation or artifact is explicit, not absent: it
  appears with `status: "MISSING"`. An expected-but-unreported artifact is likewise
  listed with `status: "MISSING"`, not omitted. This is what makes a service that
  was in scope but never attested to the binding trail show up as MISSING rather
  than vanish.
- The flag is `true` only when everything the trail's template requires is present
  and compliant, and `false` when any in-scope piece is missing or non-compliant.

For the **binding** trail, whose template lists bare artifacts with no
attestations, `is_compliant` reduces to "every in-scope artifact is present".
Because the orchestrator only binds an artifact after the service passes its gate,
that is exactly "every in-scope service built and passed its own controls".

> Note on the test suite. The `test/*.sh` system tests exercise both tiers against
> a fresh local server: the per-service gate (`kosli evaluate trail --flow
> monorepo-<x> --policy component.rego`) and the whole-commit binding gate over
> `monorepo-co-deployment`. The Kosli-behaviour facts above (MISSING semantics,
> the meaning of `is_compliant`, the array/map shapes) underpin them. See
> [findings](findings.md).

These facts are why [the gate](05-the-gate-policy.md) can be a single positive
assertion on the binding trail's flag, provided the binding template is scoped per
commit so that flag means "exactly the services this commit should have built and
gated".
