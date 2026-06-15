# Design docs: tying monorepo compliance together with Kosli

These documents explain the design in this directory and, more importantly, *why*
each decision was made. They build on each other; read in order.

1. [Problem and goals](01-problem-and-goals.md) -- what we are trying to achieve
   and the hard constraint (compliance asymmetry) that shapes everything.
2. [The Kosli model we rely on](02-kosli-model.md) -- trails, the two tiers of
   flow (per-service build flows plus the co-deployment binding flow), and
   per-trail template scoping.
3. [CI orchestration](03-ci-orchestration.md) -- the always-on scope job,
   reusable per-component workflows that each run their own SDLC and then attest
   into the binding trail, and why the barrier lives in CI, not Kosli.
4. [Per-component templates](04-template-fragments.md) -- each service owns its
   own flow template, and the binding template is generated per commit.
5. [The gate policy](05-the-gate-policy.md) -- the Rego gate over the binding
   trail, the fail-safe rules it follows, and the assert-then-attest invariant it
   relies on.
6. [Safety and trade-offs](06-safety-and-tradeoffs.md) -- the failure modes we
   designed against, the deliberate biases, and the open questions to confirm.
7. [Snyk scanning](07-snyk-scanning.md) -- how each component's .snyk policy is
   located once the repos merge, via a committed policy-map file, and the change
   needed in the shared snyk-scanning workflow.

## The shape in one diagram

```
push
 |
 v
[scope]  always runs; diff -> changed set; compose binding template;
 |  \        \         begin the monorepo-co-deployment trail
 |   \        \-- (C unchanged: build-C skipped)
 |    \
 v     v
[build-A] [build-B]   each: its own reusable workflow; runs its full SDLC in its
 |        |           own flow (monorepo-a/-b), gates with kosli assert artifact,
 |        |           then -- only if that passed -- attests its artifact into the
 |        |           shared monorepo-co-deployment trail
 \        /
  \      /
   v    v
  [gate]  needs all; if: !cancelled();
          kosli evaluate trail --flow monorepo-co-deployment --policy gate.rego
```
