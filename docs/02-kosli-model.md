# 2. The Kosli model we rely on

A short tour of the Kosli concepts this design depends on. (Reference:
https://docs.kosli.com/)

## Flow, trail, artifact, attestation

- A **flow** models a process (here, building the monorepo).
- A **trail** is one execution of that flow. We use one trail per commit, keyed
  on the commit SHA, so everything built from a commit lands in one trail.
- An **artifact** is a thing you built (a binary, image, tarball), identified by
  its SHA256 fingerprint.
- An **attestation** is a piece of evidence (a test result, a scan, a PR).

## Two scopes of attestation

The flow template declares required attestations in two places:

- **Trail-level** (`trail.attestations`): apply to the whole trail/commit. Here:
  `pull-request`. Required for the trail to be compliant.
- **Artifact-level** (`trail.artifacts[].attestations`): apply to one named
  artifact. Here: A's `unit-test`, B's `rubocop`, etc.

An attestation is bound to an artifact either by fingerprint, or -- before the
artifact exists -- by the artifact's template name plus the commit. We use the
name form (`--name A.unit-test`), so evidence can be attested as the component
builds.

## Per-trail template scoping (the key lever)

A flow has a default template, but `kosli begin trail --template-file` lets each
trail override it. We exploit this: the `scope` job composes a template
containing only the components that changed, and opens the trail with it. The
trail's notion of "complete and compliant" is therefore scoped to this commit.

## What "trail is compliant" actually means (verified)

We confirmed the following against 276 real cyber-dojo trails (read-only API):

- The compliance status is exposed at
  `input.trail.compliance_status` with `is_compliant`, `status`, a trail-level
  `attestations_statuses` array, and an `artifacts_statuses` map keyed by
  artifact name (each artifact has its own `is_compliant`, `status`, and an
  `attestations_statuses` array).
- A **missing** expected attestation is explicit, not absent: it appears with
  `status: "MISSING"`, `is_compliant: null`. You cannot be fooled by silence at
  this level.
- **`trail.compliance_status.is_compliant == true` implies every reported
  artifact is compliant** (0 counterexamples: no trail was ever green while an
  artifact was red).
- Of 215 compliant trails, **none** had a MISSING or non-compliant expected
  attestation anywhere. So the trail-level flag is a trustworthy aggregate.
- The reverse does not hold: an artifact can be green while the trail is red
  (e.g. a trail-level attestation is MISSING). So gating on a single artifact's
  flag is not sufficient; the trail-level flag is the safe thing to gate on.

These facts are why [the gate](05-the-gate-policy.md) can be a single positive
assertion on the trail-level flag -- *provided* the template is scoped per
commit so that flag means "exactly what this commit should have built".
