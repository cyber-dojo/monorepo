# 4. Per-component templates and the generated binding template

## The decision

There is no central Kosli template file. Two kinds of template exist, and they
are kept apart on purpose:

- **Each service owns its full flow template** in `source/<X>/kosli.yml`. This
  is the template for that service's own flow (`monorepo-a`, ...). It declares
  the service's trail-level attestation(s) (`pull-request`), its artifact (`A`),
  and that artifact's attestations (`A.lint`, `A.unit-test`). The service's own
  reusable workflow opens its trail with this file.
- **The binding template is generated, not authored.** `bin/scoped-template`
  emits the `monorepo-co-deployment` template for one commit: one bare artifact
  per in-scope component, no attestations. Nobody edits it by hand.

There is nothing common to centralise: with per-service flows the services share
no attestation, and the binding template carries none to merge.

## Why each service owns its own flow template

A, B and C have genuinely different toolchains and evidence, and there is no
attestation common to all three. Giving each its own flow template keeps each
service's required evidence defined exactly once, in that service's own file,
under that service's own path (`source/A/**`). Editing A's attestations touches
only A.

## Why the binding template is generated

The binding template's content is fully determined by one input: which components
are in scope this commit. There is nothing to author. `bin/scoped-template
'["A","B"]'` emits:

```yaml
version: 1
trail:
  artifacts:
    - name: A
    - name: B
```

The artifact names are the component names passed in, which are exactly the
`--name` values the services attest with. The script does not read the per-service
templates for this (their internals are irrelevant to the binding set); it only
verifies each named component has a `source/<name>/kosli.yml`, and fails loud on a
name that does not, rather than silently dropping it. So the binding template is
always scoped to exactly the changed components, never more and never less.

## Discovery: one fact, two uses

`bin/gen-filters` treats "a directory under `source/` that contains a
`kosli.yml`" as the definition of a component. So the existence of that file
drives both:

- which components exist, and
- how a change to a component is detected.

A component is detected as changed when ANY of these change:

- `source/X/**` (X's own source tree, which includes its flow template
  `source/X/kosli.yml`);
- `.github/workflows/x.yml` (X's own reusable pipeline, named by the component
  lowercased, by convention); or
- the shared orchestration files (`main.yml`, the `bin/` generators, and the
  whole `policy/` directory -- `gate.rego` and the per-service `component.rego`).

The pipeline file is watched because a change to *how* X is built and attested is
just as build-relevant as a change to X's source: without it, editing `a.yml`
would silently skip A's build. The shared files are watched by every component so
that an orchestration change rebuilds all components, see "Global edits rebuild
everything" below.

Add a component D by creating `source/D/kosli.yml` and `source/D/...`; the
filters and the binding-template composition pick it up with no other edits. (You
still add a `build-D`+`bind-D` pair and a `deploy-D` job in `main.yml`, plus a
`d.yml` workflow, because GitHub Actions cannot enumerate jobs dynamically across
reusable workflows. The per-service gate policy `policy/component.rego` is shared,
so D needs no new policy.)

## The contract with the component workflow

Within a service's own flow, the template's attestation names are the interface.
`source/A/kosli.yml` declares `lint` and `unit-test`; `a.yml` attests `A.lint` and
`A.unit-test`. If they drift, the missing one shows up as `MISSING` and A's gate
(`kosli evaluate trail --flow monorepo-a --policy component.rego`) denies. That is
the safe direction: a naming mistake fails closed inside A's flow, so the bind job
never records A in the binding trail.

Across to the binding flow, the interface is just the artifact name. A attests
`--name A` into `monorepo-co-deployment`, and the generated binding template
expects an artifact named `A`. A drift there leaves the expected `A` MISSING in
the binding trail, which the whole-commit gate denies.

## Global edits rebuild everything

A change to a shared orchestration file (`main.yml`, the `bin/` generators, or any
file under `policy/` -- both `gate.rego` and the per-service `component.rego`)
changes how *every* component is built or evaluated. `bin/gen-filters` therefore
includes those paths in every component's filter, so editing any one of them puts
all components in scope and rebuilds them.

This is the safe direction. A global orchestration or policy change that silently
rebuilt nothing could leave the commit reporting compliant against rules the
artifacts were never actually re-evaluated against. Failing toward a full rebuild
matches Kosli's asymmetry: never report compliant when it might not be.
