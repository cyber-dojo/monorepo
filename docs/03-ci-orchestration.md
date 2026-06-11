# 3. CI orchestration

The CI is in `.github/workflows/`: an orchestrator (`main.yml`) and one reusable
workflow per component (`a.yml`, `b.yml`, `c.yml`).

## Why the barrier lives in CI, not Kosli

Kosli has no wait/poll/barrier. Asserts and evaluations read the trail's current
state and return immediately. So "only judge the commit once A, B and C have all
finished" cannot be expressed in Kosli. GitHub Actions `needs` is the barrier:
the `gate` job depends on every component job and therefore runs after them.

## The always-on `scope` job

`scope` has **no path filter** -- it runs on every commit. That is deliberate and
load-bearing: only a job that always runs can notice that a component which should
have built did not. A job gated by paths cannot report its own absence.

`scope`:

1. Generates the `dorny/paths-filter` filters from the component fragments
   (`bin/gen-filters`), so "what components exist" and "how changes are detected"
   come from one place.
2. Runs the filter to get the changed set, e.g. `["A","B"]`.
3. Composes a scoped template (`bin/scoped-template`) and opens the trail with it.

It outputs `components` for the rest of the workflow to consume.

## One reusable workflow per component (not a matrix)

A `matrix` runs identical steps per value. A, B and C have genuinely different
pipelines (different languages, tools, evidence), so a matrix is the wrong tool.
Instead each component has its own reusable workflow (`on: workflow_call`) -- what
would be its `main.yml` if it lived in its own repo. The orchestrator calls each
one conditionally:

```yaml
build-A:
  needs: scope
  if: ${{ contains(fromJSON(needs.scope.outputs.components), 'A') }}
  uses: ./.github/workflows/a.yml
  with: { trail: ${{ github.sha }}, flow: monorepo }
  secrets: inherit
```

The contract between orchestrator and component is tiny:

1. The component receives the shared `trail` id and sets `KOSLI_TRAIL` from it,
   so all its attestations land in the one trail.
2. It reports an artifact named after the component (`A`) and attests `A.<name>`
   matching its fragment.
3. Only `scope` calls `kosli begin trail`; components only attest. (A component
   re-beginning the trail would clobber the scoped template.)
4. Components communicate through the trail, not through job outputs. The gate
   reads the trail, so fingerprints never have to be threaded back up.

## The gate job

```yaml
gate:
  needs: [scope, build-A, build-B, build-C]
  if: ${{ !cancelled() && needs.scope.outputs.components != '[]' }}
  ...
  run: kosli evaluate trail "$GITHUB_SHA" --flow monorepo --policy policy/gate.rego --org cyber-dojo
```

Two subtleties:

- **`!cancelled()`** is essential. If `build-C` is skipped (C unchanged) or a
  component fails, a plain `needs` would skip the gate. `!cancelled()` forces it
  to run anyway, and it then judges the trail as it actually is. A skipped C is
  fine because C is not in the scoped template; a failed B leaves B's evidence
  MISSING, so the trail is non-compliant and the gate denies. Fail-closed.
- The gate trusts the scoped template plus the trail's attested reality. It never
  inspects which jobs happened to run -- that signal is not trustworthy (see
  [doc 6](06-safety-and-tradeoffs.md)).
