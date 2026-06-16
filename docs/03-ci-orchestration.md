# 3. CI orchestration

The CI is in `.github/workflows/`: an orchestrator (`main.yml`) and one reusable
workflow per component (`web.yml`, `dashboard.yml`, `creator.yml`).

## Why the barrier lives in CI, not Kosli

Kosli has no wait/poll/barrier. Asserts and evaluations read a trail's current
state and return immediately. So "only judge the commit once A, B and C have all
finished" cannot be expressed in Kosli. GitHub Actions `needs` is the barrier:
the `gate` job depends on every component job and therefore runs after them.

## The always-on `scope` job

`scope` has **no path filter**, so it runs on every commit. That is deliberate and
load-bearing: only a job that always runs can notice that a component which should
have built did not. A job gated by paths cannot report its own absence.

`scope`:

1. Generates the `dorny/paths-filter` filters from the component fragments
   (`bin/gen-filters`), so "what components exist" and "how changes are detected"
   come from one place.
2. Runs the filter to get the changed set, e.g. `["A","B"]`.
3. Composes the co-deployment template (`bin/scoped-template`) and opens the
   `monorepo-co-deployment` trail with it.

It outputs `components` for the rest of the workflow to consume. `scope` opens
**only** the binding trail; each service opens its own build trail itself.

## One reusable workflow per component (not a matrix)

A `matrix` runs identical steps per value. A, B and C have genuinely different
pipelines (different languages, tools, evidence), so a matrix is the wrong tool.
Instead each component has its own reusable workflow (`on: workflow_call`), what
would be its `main.yml` if it lived in its own repo. The orchestrator calls each
one conditionally. The component reports only to its own flow and knows nothing of
the binding flow; it returns its flow name, artifact ref and fingerprint as
outputs for the orchestrator to gate and bind:

```yaml
build-A:
  needs: [setup, scope]
  if: ${{ contains(fromJSON(needs.scope.outputs.components), 'A') }}
  permissions: { contents: read, pull-requests: read }
  uses: ./.github/workflows/web.yml
  secrets: inherit
```

The component does not take the binding flow/trail as inputs; the orchestrator
owns every write to the binding trail, in the bind job below.

The `permissions` block is on the calling job, not workflow-wide: a job that
calls a reusable workflow caps that workflow's `GITHUB_TOKEN`, and A's
`pull-request` attestation needs `pull-requests: read`. Keeping it on the three
callers leaves `scope`/`gate` at least privilege.

## What each component workflow does

Each component workflow runs its own complete SDLC against its own flow, and
reports only there -- it does not know the binding flow exists:

1. Opens its own trail: `kosli begin trail "${KOSLI_TRAIL}"` (the commit SHA) in
   its own flow (`KOSLI_FLOW: monorepo-web`), with its own template
   `source/web/kosli.yml`.
2. Attests its own evidence into that flow: `pull-request`, the artifact `A`, and
   the artifact attestations (`A.lint`, `A.unit-test`).
3. Returns its flow name, the artifact ref, and the artifact fingerprint as
   workflow outputs, for the orchestrator to gate and bind.

## The bind job

For each in-scope component the orchestrator runs a `bind-<X>` job that gates the
service and, only on success, records it in the co-deployment set:

1. Gates the service's own flow: `kosli evaluate trail "$KOSLI_TRAIL" --flow
   ${{ needs.build-A.outputs.flow }} --policy policy/component.rego --assert`. A
   non-compliant service flow exits non-zero and stops the job here.
2. Only if that gate passed, attests the artifact into the shared trail by
   fingerprint: `kosli attest artifact ${{ needs.build-A.outputs.image }}
   --fingerprint ${{ needs.build-A.outputs.fingerprint }} --name A --flow
   ${{ needs.setup.outputs.kosli_flow }} --trail
   ${{ needs.setup.outputs.kosli_trail }}`. The positional artifact ref is
   required even with `--fingerprint`; with the fingerprint supplied the CLI uses
   it only as the artifact's filename and never opens the file (which the bind job
   does not have). This is the one write to the binding trail, and it records A in
   this commit's co-deployment set.

Both steps run in one `set -euo pipefail` block, so the attest is unreachable
unless the evaluate `--assert` passed. The bind job lives next to its build job in
`main.yml`, so adding a service is a copy-paste of one build+bind pair.

Two consequences worth stating:

- The evaluate-then-bind ordering is the whole tie-together mechanism. A service
  that fails its own gate never reaches the bind attestation, so its artifact
  stays MISSING in the binding trail. There is no path by which a service
  contributes to the binding set without having passed its controls.
- The whole-commit gate never reads the per-service flows. The bind job evaluates
  each service flow once to decide whether to record it; the gate then judges only
  the binding trail. The fingerprint is threaded from the build job's output into
  its bind job; nothing else crosses between flows.

## The gate job

```yaml
gate:
  needs: [scope, bind-A, bind-B, bind-C]
  if: ${{ !cancelled() && needs.scope.outputs.components != '[]' }}
  run: kosli evaluate trail "$KOSLI_TRAIL" --policy policy/gate.rego --assert
        # KOSLI_FLOW: monorepo-co-deployment
```

Two subtleties:

- **`!cancelled()`** is essential. If `build-C`/`bind-C` is skipped (C unchanged)
  or a component fails, a plain `needs` would skip the gate. `!cancelled()` forces
  it to run anyway, and it then judges the binding trail as it actually is. A
  skipped C is fine because C is not in the binding template; a failed B never
  gets bound into the binding trail, so B is MISSING there, the trail is
  non-compliant, and the gate denies. Fail-closed.
- The gate trusts the binding template plus the binding trail's attested reality.
  It never inspects which jobs happened to run, because that signal is not
  trustworthy (see [doc 6](06-safety-and-tradeoffs.md)).
