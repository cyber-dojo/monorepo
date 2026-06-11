# 1. Problem and goals

## The situation

A monorepo contains several independently buildable components -- here A, B and C
under `source/`. Each has its own toolchain, its own tests, and its own set of
Kosli attestations. There are no attestations common to all three.

A commit may touch any subset of them. Each component's CI only runs when its own
files change, so a single commit might build just A and B, leaving C untouched.

## What we want

Tie the compliance of the components built from one commit together, so that the
commit as a whole is judged compliant only when **every component it should have
built is itself compliant** -- even though the components share no attestation.

Concretely:

- A and B changed, C did not -> the commit is compliant iff A and B are both
  compliant. C is irrelevant to this commit. (Proved both ways:
  `test/test_two_components_all_compliant.sh`,
  `test/test_two_components_one_not_compliant.sh`; a trail scoped to a subset is
  compliant on its own: `test/test_green_path_all_compliant.sh`.)
- A changed and is compliant, B changed but is missing an attestation -> the
  commit is non-compliant, because B was in scope and is not compliant. (Proved:
  `test/test_two_components_one_not_compliant.sh`.)
- A component that *should* have built but silently did not must make the commit
  non-compliant. Silence is never success. (Proved:
  `test/test_in_scope_artifact_never_reported.sh`.)

## The hard constraint: compliance is asymmetric

This is the rule that shapes every later decision:

> Reporting something non-compliant when it is actually compliant is acceptable
> (annoying, recoverable). Reporting something compliant when it is actually
> non-compliant must never happen (it passes a bad build, unrecoverable).

So whenever a design choice trades off "might wrongly block a good commit" against
"might wrongly pass a bad commit", we always choose the first. You will see this
play out as:

- default-deny policies that demand positive proof of compliance,
- a scope computation biased toward over-inclusion,
- treating "missing / didn't run" as non-compliant rather than ignorable.

## Why this is not trivial

Two facts make it harder than "just check the trail":

1. **Kosli has no wait/barrier.** Every assert/evaluate command reads the trail's
   current state and exits immediately. There is no `kosli assert trail` and no
   `--wait`. So you cannot ask Kosli to "block until A, B and C are all done".
   The synchronization has to come from CI. See [doc 3](03-ci-orchestration.md).

2. **Scope varies per commit.** Because builds are path-filtered, "which
   components are in play" changes commit to commit. A fixed policy that always
   expects A, B and C would wrongly fail every commit that legitimately touched
   only some of them. So the template must be scoped per commit, and that scope
   must come from an authoritative source. See [doc 4](04-template-fragments.md).
