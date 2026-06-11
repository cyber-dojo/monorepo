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

## What "trail is compliant" actually means (proved against a fresh server)

- The compliance status is exposed at `input.trail.compliance_status` with
  `is_compliant`, `status`, a trail-level `attestations_statuses` array, and an
  `artifacts_statuses` map keyed by artifact name (each artifact has its own
  `is_compliant`, `status`, and an `attestations_statuses` array).
- A **missing** expected attestation is explicit, not absent: it appears with
  `status: "MISSING"`. Proved by `test/test_missing_artifact_attestation.sh`. An
  expected-but-unreported artifact is likewise listed with `status: "MISSING"`,
  not omitted (`test/test_in_scope_artifact_never_reported.sh`).
- A missing TRAIL-level attestation makes the trail non-compliant and, on the
  current server, drags the reporting artifact to non-compliant too. Proved by
  `test/test_artifact_compliance_when_trail_attestation_missing.sh`. (Older
  production trails behaved inconsistently here; see [findings](findings.md).
  That inconsistency is exactly why we gate on the trail-level flag rather than a
  single artifact's flag -- the trail-level flag is the complete aggregate of
  every trail-level attestation plus every artifact.)
- The flag is `true` only when everything required is present and compliant, and
  `false` when any in-scope piece is missing or non-compliant. Proved both ways
  by `test/test_two_components_all_compliant.sh` and
  `test/test_two_components_one_not_compliant.sh`.

These facts are why [the gate](05-the-gate-policy.md) can be a single positive
assertion on the trail-level flag -- *provided* the template is scoped per
commit so that flag means "exactly what this commit should have built".
