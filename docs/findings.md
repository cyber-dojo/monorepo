# Findings: empirical speed bumps and confirmed behaviour

A running log of things learned by driving a FRESH local Kosli server with the
real CLI (see `test/`). Each entry is dated and version-stamped, because the
Kosli server changes constantly and these can go stale.

Context unless stated otherwise:
- kosli CLI `2.24.2`
- local demo server from `kosli-dev/server` (`make demo_empty`), on `http://localhost:80`
- org `test-organization`, ci-reporter service-account token
- date: 2026-06-11

## CLI / policy requirements

- **`kosli evaluate` policies must use `package policy`** and define an `allow`
  rule. `package gate` (or any other name) is rejected. (Fixed in
  `policy/gate.rego`.)
- **`kosli evaluate trail|input` asserts on deny by default (`--assert`), but the
  default will flip to `--no-assert`** in a future release. Pass `--assert`
  explicitly to lock in exit-non-zero-on-deny for gating.
- **`kosli attest artifact` requires `--build-url`** (in addition to
  `--commit` / `--commit-url`). A fake value is acceptable for tests.
- **attest flag sets differ per command.** `--commit-url` and `--build-url`
  exist on `kosli attest artifact` (and `--build-url` is required there), but
  `kosli attest generic` / `attest junit` REJECT `--commit-url` ("unknown flag")
  and have no `--build-url`. They associate to a commit via `--commit` (resolved
  against `--repo-root`) and use `--origin-url` (`-o`) for the source URL. So the
  git/commit flags must be split per attestation command, not shared across them.

## Git-repo reliance (RESOLVED from CLI source: kosli-dev/cli)

How attest commands get commit/repo info (traced in the CLI source):
- `cmd/kosli/attestation.go` (~line 81): commit info is fetched ONLY when a
  commit SHA is set, via `gitview.GetCommitInfoFromCommitSHA`.
- `internal/gitview/gitView.go` (~line 195): that function ALWAYS reads a real
  local git repo through go-git -- it resolves the SHA and reads the commit's
  author / branch / message / timestamp / parents from the repository. There is
  NO env-var path for commit *content*.
- `cmd/kosli/cli_utils.go`: env/CI only DEFAULTS the flag *values* --
  `WhichCI()` detects the provider by env-var (GitHub via `GITHUB_RUN_NUMBER`),
  and `ciTemplates` maps flags to env (e.g. `--commit`=`$GITHUB_SHA`,
  `--build-url`, `--commit-url`, `--repo-url`, `--repo-id`, `--repo-provider`).
  Setting `KOSLI_TESTS` (or `DOCS`) makes `DefaultValue` return "" -> disables
  that defaulting.

Implication: "flags only, NO git repo" is not possible for a commit-bearing
attestation -- the commit's content must come from a real repo. So complete,
hermetic control is achieved by:
1. building a CONTROLLED, disposable git repo in the test's temp dir (author
   exactly the commit(s) we want), and
2. pointing every command at it with `--repo-root <tmp-repo>` (default is `.`,
   the cwd -- which is the ambient "repo under you" we must avoid), and
3. passing repo/url/build-url info as EXPLICIT flags (`--commit`, `--commit-url`,
   `--build-url`, `--repo-url`, `--repo-provider`, ...) so nothing is silently
   defaulted from whatever ambient CI env happens to be set.

This is hermetic and deterministic, and scales to the future "workflow across
more than one commit" tests: make several commits in the controlled repo and
drive attests with the matching `--commit` + `--repo-root`.

Useful knobs found:
- `--repo-root` (default `.`) selects the git repo read for commit info.
- `--commit` / `-g` defaults from CI env (e.g. `$GITHUB_SHA`).
- `KOSLI_TESTS` env disables all CI flag-defaulting (used by the CLI's own tests).

## Confirmed response shapes / behaviour

- **`kosli get trail --output json`** has compliance at the top level:
  ```
  .compliance_status.is_compliant            bool
  .compliance_status.status                  "COMPLIANT" | "INCOMPLETE" | ...
  .compliance_status.attestations_statuses   [ {attestation_name, status, is_compliant, unexpected}, ... ]  # trail-level
  .compliance_status.artifacts_statuses      { "<name>": { is_compliant, status, attestations_statuses:[...] } }  # map
  ```
  The jq paths in `test/` resolve against this directly.
- **A missing trail-level attestation appears explicitly** as
  `status: "MISSING"` (not absent), and the trail's `.is_compliant` is `false`.
  `gate.rego` correctly denies. (Observed via the live CLI, fresh server.)
## RESOLVED: artifact compliance when a trail-level attestation is MISSING

Settled by `test/test_service_gate_fails_when_trail_attestation_missing.sh`
(renamed from `test_artifact_compliance_when_trail_attestation_missing.sh` in the
two-tier rework) against a fresh local server (CLI 2.24.2, 2026-06-11):

With artifact A *fully* attested (`A.lint` + `A.unit-test` both present and
compliant) but the trail-level `pull-request` MISSING:
- `.compliance_status.artifacts_statuses.A.is_compliant = false`
- `.compliance_status.is_compliant (trail)             = false`
- trail-level `pull-request` status = `MISSING`

So on the current server a missing TRAIL-level attestation drags the ARTIFACT to
non-compliant, even though the artifact's own attestations all pass.

This deliberately contradicts the old production trails we looked at earlier,
which were inconsistent (`tf-plan-*` left the artifact COMPLIANT while missing;
`never-alone-*` dragged it NON-COMPLIANT). Those were created at different dates
against different server versions -- exactly why we re-tested on a fresh server.
The test now pins the current behaviour so a future change is caught.

## Verified by the system-test suite (claim -> proving test)

The suite is the two-tier set (reworked 2026-06-15; see the topology entry below).
All against a fresh local server; each row is asserted, not assumed. Whole suite
green on CLI 2.24.2, 2026-06-15: 9 system tests (96 checks) + 2 server-free script
tests (31 checks), 0 failed.

Tier 1 -- per-service build flow, gated by the service's own `kosli assert
artifact` (the self-check in a.yml/b.yml/c.yml):

- Self-check PASSES only when the service flow is genuinely compliant (positive
  control) -> `test/test_service_gate_passes_when_compliant.sh`
- A missing artifact-level attestation -> artifact non-compliant + self-check
  denies -> `test/test_service_gate_fails_on_missing_attestation.sh`
- A present-but-failing attestation (`--compliant=false`) -> non-compliant +
  self-check denies -> `test/test_service_gate_fails_on_failing_attestation.sh`
- A missing trail-level attestation drags the artifact non-compliant + self-check
  denies -> `test/test_service_gate_fails_when_trail_attestation_missing.sh`
- An UNEXPECTED attestation (not in the template) that is non-compliant STILL
  makes the artifact non-compliant and denies the self-check. "Unexpected" means
  "not required", NOT "ignored": a known-bad ad-hoc attestation cannot be sneaked
  past the service gate. (A *compliant* unexpected attestation -- e.g. historical
  provenance/sbom -- does not affect compliance.) ->
  `test/test_service_gate_fails_on_unexpected_noncompliant.sh`

Tier 2 -- binding trail (monorepo-co-deployment), gated by `kosli evaluate trail`:

- Every in-scope artifact present -> binding compliant + gate allows (positive
  control) -> `test/test_binding_gate_allows_when_all_present.sh`
- An in-scope artifact absent from the binding trail (failed its own gate, or
  never ran) -> binding non-compliant + gate denies; it appears in
  `artifacts_statuses` with `status: "MISSING"` (NOT omitted). One test covers
  both "ran but failed" and "never reported", which under the binding model are
  the same MISSING artifact ->
  `test/test_binding_gate_denies_when_in_scope_artifact_missing.sh`
- A binding trail scoped to a subset is compliant on its own (a commit that built
  only A expects only A) -> `test/test_binding_gate_allows_scoped_subset.sh`

Tier 3 -- the cross-tier assert-then-attest invariant:

- A service attests its artifact into the binding trail ONLY after passing its own
  gate. A passes and attests; B fails and never attests, so B is MISSING in the
  binding trail and the whole-commit gate denies. This is the docs/06 trust
  boundary, proved end to end ->
  `test/test_failed_service_gate_keeps_artifact_out_of_binding.sh`

Server-free generator tests (no server needed):
- `bin/scoped-template` composes the binding template as bare artifacts (one per
  in-scope component, no attestations), and fails loud on an unknown component ->
  `test/scripts/test_scoped_template.sh`
- `bin/gen-filters` derives each component's filter from its fragment file: it
  watches `source/X/**`, the component's own workflow `.github/workflows/x.yml`,
  and the shared orchestration paths (no longer the removed `kosli/trail.yml`) ->
  `test/scripts/test_gen_filters.sh`

## Topology change: single shared flow -> per-service flows + a binding flow (2026-06-15)

The design moved from one shared `monorepo` flow (every component a named
artifact in one per-commit trail) to two tiers of flow:

- per-service build flows `monorepo-a` / `-b` / `-c`, each holding that service's
  full SDLC evidence (`pull-request`, the artifact, its attestations) and its own
  gate (`kosli assert artifact`); template `source/<X>/kosli.yml`; and
- a binding flow `monorepo-co-deployment` whose per-commit trail records only the
  co-deployment set: one bare artifact per in-scope component, no attestations. A
  service attests its artifact there only after passing its own gate. The
  whole-commit gate (`kosli evaluate trail --flow monorepo-co-deployment`) keys on
  that one trail. This is the doc-07 "Topology B".

What this meant for the suite:

- The Kosli-behaviour facts (MISSING is explicit not absent; `is_compliant`
  meaning; array/map shapes; unexpected-attestation handling;
  `--assert`/`--build-url`/per-command flag quirks; the git-repo reliance) are
  unchanged and still hold.
- The suite was reworked to the two-tier model the same day (the section above is
  the new mapping). The old single-shared-flow tests
  (`test_green_path_all_compliant.sh`, `test_missing_artifact_attestation.sh`,
  `test_in_scope_artifact_never_reported.sh`, `test_failing_attestation.sh`,
  `test_two_components_all_compliant.sh`, `test_two_components_one_not_compliant.sh`,
  `test_artifact_compliance_when_trail_attestation_missing.sh`,
  `test_unexpected_attestation.sh`) were replaced by Tier-1 per-service tests,
  Tier-2 binding-trail tests, and a Tier-3 cross-tier test, all green.
- Newly proven by the rework and not provable under the single-flow design: a BARE
  artifact (no required attestations) is compliant once present, so the binding
  trail's `is_compliant` reduces to "every in-scope artifact present"; and the
  assert-then-attest ordering keeps a failed service's artifact out of the binding
  trail (Tier-3).
- `bin/scoped-template` now emits the binding template (bare artifacts from the
  component names), not a union of the fragments;
  `test/scripts/test_scoped_template.sh` was updated to match.
