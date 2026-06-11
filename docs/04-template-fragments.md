# 4. Per-component template fragments

## The decision

The Kosli template is **not** one central file. Each component owns a small
fragment (`source/<X>/kosli.yml`) describing only its own artifact and
attestations. The shared trail-level part lives in `kosli/trail.yml`. The
`scope` job unions the in-scope fragments into a per-commit template.

## Why not one central template file

A single file listing A, B and C has two problems:

1. **False coupling on edits.** Editing A's section is, at the file level,
   indistinguishable from editing B's. You cannot path-filter *within* a file.
2. **The trigger problem.** To make a template change rebuild the right
   component you would have to include the central file in every component's path
   filter -- so editing A's attestations would needlessly rebuild B and C.

Decomposing fixes both. `source/A/kosli.yml` lives under `source/A/**`, so
editing it puts only A in scope. B and C are untouched.

## How the union works

`bin/scoped-template '["A","B"]'`:

1. loads `kosli/trail.yml` (trail-level attestations, empty artifact list),
2. appends `source/A/kosli.yml` and `source/B/kosli.yml` as artifact entries,
3. writes the result to stdout.

The scoped template is always a strict *subset* of the fragments. Each
component's required attestations are defined exactly once, in its own fragment,
and only ever filtered here -- never re-authored. There is no combined copy to
keep in sync.

## Discovery: one fact, two uses

`bin/gen-filters` treats "a directory under `source/` that contains a
`kosli.yml`" as the definition of a component, and emits `X: ['source/X/**']` for
each. So the existence of the fragment file drives both:

- which components exist, and
- how a change to a component is detected.

Add a component D by creating `source/D/kosli.yml` and `source/D/...`; the
filters and the template composition pick it up with no other edits. (You still
add a `build-D` caller job and a `d.yml` workflow -- GitHub Actions cannot
enumerate jobs dynamically across reusable workflows.)

## The contract with the component workflow

The fragment's attestation names are the interface. `source/A/kosli.yml` declares
`lint` and `unit-test`; `a.yml` attests `A.lint` and `A.unit-test`. If they drift,
the missing one shows up as `MISSING` -> non-compliant. That is the safe
direction: a naming mistake fails closed, it does not silently pass.

## The trail-level edit edge case

Editing `kosli/trail.yml` sits under no component path, so by default it rebuilds
nothing. That is usually fine: the `scope` job always runs and composes the new
trail-level rules on the next commit regardless, and trail-level attestations
(like `pull-request`) are produced by the orchestrator, not the component builds.

If you ever want a trail-rule change to force every component to re-attest against
the new global policy, add `kosli/trail.yml` to every component's path filter on
purpose. That is a rare "global compliance policy changed" event where a full
rebuild is the correct, safe response.
