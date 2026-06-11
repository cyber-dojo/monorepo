# Design docs: tying monorepo compliance together with Kosli

These documents explain the design in this directory and, more importantly, *why*
each decision was made. They build on each other; read in order.

1. [Problem and goals](01-problem-and-goals.md) -- what we are trying to achieve
   and the hard constraint (compliance asymmetry) that shapes everything.
2. [The Kosli model we rely on](02-kosli-model.md) -- trails, artifact vs
   trail-level attestations, and per-trail template scoping.
3. [CI orchestration](03-ci-orchestration.md) -- the always-on scope job,
   reusable per-component workflows, and why the barrier lives in CI, not Kosli.
4. [Per-component template fragments](04-template-fragments.md) -- why the
   template is decomposed per component and unioned at scope time.
5. [The gate policy](05-the-gate-policy.md) -- the Rego gate, the fail-safe
   rules it follows, and the real cyber-dojo data that justifies it.
6. [Safety and trade-offs](06-safety-and-tradeoffs.md) -- the failure modes we
   designed against, the deliberate biases, and the open questions to confirm.

## The shape in one diagram

```
push
 |
 v
[scope]  always runs; diff -> changed set; compose scoped template; begin trail
 |  \        \
 |   \        \-- (C unchanged: build-C skipped)
 |    \
 v     v
[build-A] [build-B]   each: its own reusable workflow; attests into the shared trail
 \        /
  \      /
   v    v
  [gate]  needs all; if: !cancelled(); kosli evaluate trail --policy gate.rego
```
