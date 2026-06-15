# cyber-dojo monorepo (Kosli compliance example)

A worked example of tying the Kosli compliance of several monorepo components
(A, B, C) together for a single commit, when each component has its own bespoke
CI pipeline and its own attestations, and only the components that changed are
built. Deployment is all-or-nothing: every changed component is deployed only if
the whole commit is compliant, and if any one of them fails, nothing is deployed.

## Layout

```
source/A, source/B, source/C   each component: source + build.sh + its own flow template kosli.yml
bin/scoped-template             compose the per-commit co-deployment binding template (bare artifacts)
bin/gen-filters                 derive the path filters from the component dirs
policy/gate.rego                the whole-commit compliance gate (kosli evaluate trail)
.github/workflows/main.yml      orchestrator: scope -> per-component build -> gate -> per-component deploy
.github/workflows/a|b|c.yml     each component's own reusable build pipeline (its own Kosli flow)
.github/workflows/deploy.yml    shared reusable deploy workflow, called once per rebuilt artifact
docs/                           the full design and the reasons for it
```

## The one-paragraph version

There are two tiers of Kosli flow. Each component builds in its **own** flow
(`monorepo-a`, `monorepo-b`, `monorepo-c`), where it attests its full evidence
(pull-request, the artifact, its tests and lint) and gates itself with
`kosli assert artifact`. A second **binding** flow, `monorepo-co-deployment`,
records only the co-deployment set for the commit.

A single always-on `scope` job works out which components changed, composes the
binding template listing exactly those components as bare artifacts, and opens the
`monorepo-co-deployment` trail keyed on the commit SHA. Each changed component's
reusable workflow runs its own pipeline and, **only after** passing its own
self-check, attests its artifact into that shared binding trail (the
assert-then-attest invariant). A `gate` job then runs `kosli evaluate trail` over
the binding trail against `policy/gate.rego`, which passes only if every in-scope
artifact is present; because each was attested post-gate, present means
compliant. Finally each rebuilt component is deployed, identified by the
image+fingerprint its build workflow returned. Components that did not change are
not in the template, so they are neither waited on nor deployed. The
synchronization is GitHub Actions `needs`, because Kosli has no wait/barrier
primitive.

## Read the docs

Start at [docs/00-index.md](docs/00-index.md). The split into per-service flows
plus a binding flow, and why `kosli evaluate trail` judges a single trail, are in
[docs/02-kosli-model.md](docs/02-kosli-model.md).

## Status

- The component builds are deterministic stand-ins so the wiring is runnable
  without real toolchains, and `deploy.yml` is a placeholder deploy step.
- The Kosli commands assume a `KOSLI_API_TOKEN` secret and the `cyber-dojo` org.
- The field paths in `policy/gate.rego` were confirmed against real cyber-dojo
  trail data; see [docs/05-the-gate-policy.md](docs/05-the-gate-policy.md).
- The test suite is the two-tier set under `test/` (per-service gate, binding
  gate, and a cross-tier assert-then-attest test), green against a fresh local
  Kosli server.
- By design the per-component `pull-request` attestation is non-compliant on a
  direct push with no PR, which fail-closes the self-check; exercise the workflow
  via a pull request.
