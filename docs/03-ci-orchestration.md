# 3. CI orchestration

The CI is in `.github/workflows/`: an orchestrator (`main.yml`) and one reusable
workflow per component (`a.yml`, `b.yml`, `c.yml`).

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
one conditionally and passes the binding flow and trail in:

```yaml
build-A:
  needs: [setup, scope]
  if: ${{ contains(fromJSON(needs.scope.outputs.components), 'A') }}
  permissions: { contents: read, pull-requests: read }
  uses: ./.github/workflows/a.yml
  with:
    kosli_flow:  ${{ needs.setup.outputs.kosli_flow }}   # monorepo-co-deployment
    kosli_trail: ${{ needs.setup.outputs.kosli_trail }}  # the commit SHA
  secrets: inherit
```

The `permissions` block is on the calling job, not workflow-wide: a job that
calls a reusable workflow caps that workflow's `GITHUB_TOKEN`, and A's
`pull-request` attestation needs `pull-requests: read`. Keeping it on the three
callers leaves `scope`/`gate` at least privilege.

## What each component workflow does

Each component workflow runs its own complete SDLC against its own flow, then
contributes to the binding trail:

1. Opens its own trail: `kosli begin trail "${KOSLI_TRAIL}"` (the commit SHA) in
   its own flow (`KOSLI_FLOW: monorepo-a`), with its own template
   `source/A/kosli.yml`.
2. Attests its own evidence into that flow: `pull-request`, the artifact `A`, and
   the artifact attestations (`A.lint`, `A.unit-test`).
3. Runs its own gate: `kosli assert artifact source/A/dist/A.tar`. A non-compliant
   artifact fails this step, which fails the job and stops it here.
4. Only if that gate passed, attests its artifact into the shared trail:
   `kosli attest artifact ... --name A --flow ${{ inputs.kosli_flow }} --trail
   ${{ inputs.kosli_trail }}`. This is the one cross-flow write, and it records A
   in this commit's co-deployment set.

Two consequences worth stating:

- The assert-then-attest ordering is the whole tie-together mechanism. A service
  that fails its own gate never reaches step 4, so its artifact stays MISSING in
  the binding trail. There is no path by which a service contributes to the
  binding set without having passed its controls.
- The binding gate never reads the per-service flows. Components communicate to
  the gate only through the binding trail, so fingerprints and verdicts never have
  to be threaded back up through job outputs.

## The gate job

```yaml
gate:
  needs: [scope, build-A, build-B, build-C]
  if: ${{ !cancelled() && needs.scope.outputs.components != '[]' }}
  run: kosli evaluate trail "$KOSLI_TRAIL" --policy policy/gate.rego --assert
        # KOSLI_FLOW: monorepo-co-deployment
```

Two subtleties:

- **`!cancelled()`** is essential. If `build-C` is skipped (C unchanged) or a
  component fails, a plain `needs` would skip the gate. `!cancelled()` forces it
  to run anyway, and it then judges the binding trail as it actually is. A skipped
  C is fine because C is not in the binding template; a failed B never attests to
  the binding trail, so B is MISSING there, the trail is non-compliant, and the
  gate denies. Fail-closed.
- The gate trusts the binding template plus the binding trail's attested reality.
  It never inspects which jobs happened to run, because that signal is not
  trustworthy (see [doc 6](06-safety-and-tradeoffs.md)).
