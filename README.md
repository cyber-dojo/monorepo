# cyber-dojo monorepo (Kosli compliance example)

A worked example of tying the Kosli compliance of several monorepo components
(A, B, C) together for a single commit, when each component has its own bespoke
CI pipeline and its own attestations, and only the components that changed are
built.

## Layout

```
source/A, source/B, source/C   each component: source + build.sh + kosli.yml fragment
kosli/trail.yml                 shared trail-level template skeleton
bin/scoped-template             compose a per-commit template (subset of fragments)
bin/gen-filters                 derive the path filters from the fragments
policy/gate.rego                the whole-commit compliance gate (kosli evaluate trail)
.github/workflows/main.yml      orchestrator: scope -> per-component builds -> gate
.github/workflows/a|b|c.yml     each component's own reusable pipeline
docs/                           the full design and the reasons for it
```

## The one-paragraph version

A single always-on `scope` job works out which components changed, composes a
Kosli trail template containing exactly those components (by unioning their
per-component `kosli.yml` fragments), and opens one trail keyed on the commit
SHA. Each changed component's reusable workflow attests its artifact and evidence
into that shared trail. A final `gate` job runs `kosli evaluate trail` against
`policy/gate.rego`, which passes only if the whole scoped trail is compliant.
Components that did not change are simply not in the template, so they are not
waited on. The synchronization is done by GitHub Actions `needs`, because Kosli
has no wait/barrier primitive.

## Read the docs

Start at [docs/00-index.md](docs/00-index.md).

## Status

The component builds are deterministic stand-ins so the wiring is runnable
without real toolchains. The Kosli commands assume a `KOSLI_API_TOKEN` secret and
the `cyber-dojo` org. The field paths in `policy/gate.rego` were confirmed against
real cyber-dojo trail data; see [docs/05-the-gate-policy.md](docs/05-the-gate-policy.md).
