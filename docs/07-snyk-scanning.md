# Snyk scanning in the monorepo: locating each component's .snyk policy

## Summary: what needs to be done

When `creator`, `dashboard` and `web` move into one monorepo, the shared snyk
scanning workflow can no longer find each component's `.snyk` policy file,
because it assumes the policy lives at the repo root. The fix has three parts:

1. Add a policy-map file at the monorepo root, read at the artifact's commit,
   that maps each component to the path of its `.snyk` file.
2. Move the policy-locating logic into `artifact_snyk_test.yml` so it reads the
   map and resolves the right `.snyk` path itself. Replace the
   `raw_snyk_policy_url` input with an optional `commit_url` input.
3. Make a declared-but-unreadable policy fail the job loudly, instead of the
   current silent fallback to an empty policy.

Nothing here is implemented yet. This document is the agreed design so a later
session can pick it up.

## Background: the root-`.snyk` assumption

The reusable workflow is
`cyber-dojo/snyk-scanning/.github/workflows/artifact_snyk_test.yml`. It locates
the policy file via one input default (lines 77-81):

```
raw_snyk_policy_url:
  default: https://raw.githubusercontent.com/${{github.repository}}/${{github.sha}}/.snyk
```

The hardcoded `/.snyk` suffix assumes "one repo, one component, one `.snyk` at
the root". That is true by construction in the current polyrepo world, so it was
never wrong and never made explicit. In a monorepo the three policies live at
`source/creator/.snyk`, `source/dashboard/.snyk`, `source/web/.snyk`, and the
root URL 404s.

### What actually happens to the fetched file (important)

The snyk CLI never sees the real policy. The ordering in `find-snyk-vulns` is:

1. Create an empty `.snyk` (lines 170-172).
2. Run `snyk container test --policy-path=.snyk` against that empty file
   (lines 174-181).
3. Only then curl the real `.snyk` into the same filename (lines 196-205).
4. Pass the real `.snyk` to `bin/combine_snyk.py` (lines 212-223), which reads
   it as YAML (`argv[5]`, opened at combine_snyk.py:54-55) and applies the
   `ignore` entries in post-processing.

So the snyk CLI argument fussiness is irrelevant: `--policy-path` is always a
constant local empty `.snyk`. The real policy only needs to land at
`$GITHUB_WORKSPACE/.snyk` for `combine_snyk.py` to open it. The monorepo change
is purely about the curl URL, not the snyk argument or the save location.

There are two curl sites that both need the same resolution logic:
`find-snyk-vulns` (lines 196-205) and `attest-snyk-vulns` (lines 408-415).

## The two consumers, and why the second is the hard one

`artifact_snyk_test.yml` is called from two very different places.

1. Build time, for example `creator/.github/workflows/main.yml`
   (`snyk-container-scan` job, needs `[setup, build-image]`, line 140). Here the
   caller knows the component, and `github.repository` plus `github.sha` already
   point at the monorepo and the build commit. The policy path is easy to supply.

2. Live runtime scanning of an environment, for example
   `snyk-scanning/.github/workflows/aws-beta.yml`, which calls
   `env_snyk_test.yml`, which fans out one `artifact_snyk_test.yml` job per
   running image (matrix at env_snyk_test.yml:49-66). Here there is no caller who
   knows the layout. The per-image `raw_snyk_policy_url` is computed in
   `bin/artifacts.py` from a Kosli environment snapshot:
   - component identity is recovered by string-munging the build flow name:
     `repo_name = flow_name[:-3]` (artifacts.py:54), for example
     `creator-ci` -> `creator`.
   - the policy URL is built from the artifact's commit URL and hardcodes
     `/.snyk` at the root (artifacts.py:69-85).

   In a monorepo the artifact's `commit_url` points at the monorepo, so
   `artifacts.py` builds `.../cyber-dojo-monorepo/<sha>/.snyk`, which is the
   monorepo root and does not exist. The subdirectory `source/creator/` is new
   information that cannot be derived from the commit URL.

This is why "let the caller pass the path" is necessary but not sufficient: the
live scan has no such caller.

### Identifying the component in the live scan depends on the monorepo flow topology

A second monorepo concern, separate from the policy path: how the live scan
recovers *which component* each running image is. Today it reads the flow name --
`repo_name = flow_name[:-3]` (artifacts.py:54, `creator-ci` -> `creator`) -- and
`is_build_flow` (artifacts.py:101-106) only processes artifacts whose flow is in
the `BUILD_FLOWS` allowlist (artifacts.py:88-99: `creator-ci`, `dashboard-ci`,
`web-ci`, ...). For any repo that stays polyrepo this is unchanged.

Whether it still works for the *migrated* components (web/creator/dashboard)
depends on a broader design decision that is **not a snyk decision**: the Kosli
flow topology of the monorepo (docs [02](02-kosli-model.md)-[05](05-the-gate-policy.md)).
That decision has now been made in favour of **Topology B** (per-service build
flows plus a `monorepo-co-deployment` binding flow); docs 02-05 are written to it.
The two candidate topologies are kept below as the rationale, and because the
exact per-service flow *names* for the real services (whether the `*-ci` names
survive, or become `monorepo-*`) still need confirming, which is what decides the
`flow_name[:-3]` behaviour. Two candidate topologies have opposite consequences
here.

**Topology A -- one shared `monorepo` flow** (the superseded design; docs 02-05
no longer describe it).
Components are named artifacts in one per-commit trail; the gate is a single
assertion on the trail-level flag, which aggregates *every* artifact in the trail
(`02:46-56`, `05:14-16`), so `web` fails when `creator` (same commit) is
non-compliant. That cross-artifact aggregation needs one shared trail, hence one
flow (`02:9`, `03:42`, `03:64`). Under A:

- every migrated component's snapshot `flow_name` is `monorepo`, so
  `flow_name[:-3]` returns the same garbage for all of them; and
- **the silent-skip risk (the dangerous part):** `monorepo` is not in
  `BUILD_FLOWS`, so `is_build_flow("monorepo")` is `False` and `artifacts.py`
  drops web/creator/dashboard from the matrix altogether. The sweep would then
  **never scan the migrated components**. An unscanned artifact produces no
  finding, which reads as "nothing to report", not as a failure -- silently
  inverting the compliance asymmetry of `01-problem-and-goals.md` (an artifact
  never scanned can never be flagged non-compliant). It is worse than a wrong
  policy path, because nothing in the output signals the gap.

  So under A the live scan must (1) recognize the `monorepo` flow in
  `is_build_flow`/`BUILD_FLOWS`, and (2) take component identity (`repo_name` and
  the map key) from `template_reference_name` (the artifact's name in the shared
  trail, `03:50`), since `flow_name` no longer distinguishes components.

**Topology B -- per-component build flows plus a binding flow.** `web.yml` still
attests web's build and artifact to `web-ci`, `creator.yml` to `creator-ci`, etc.;
a separate per-commit *binding* flow carries one compliance-summary attestation
per built artifact and its gate aggregates those (this is workable only if each
component pushes its own verdict into the binding trail, because
`kosli evaluate trail` judges a single trail and cannot read another flow's
compliance). Under B the `*-ci` flows survive, so in the snapshot each migrated
image still carries its `web-ci`/`creator-ci` build flow:
`is_build_flow("web-ci")` is already true and `flow_name[:-3]` -> `web` keeps
working. **There is no silent-skip and no identity change** -- the only caveat is
to keep the binding flow out of `BUILD_FLOWS` so it is not mistaken for a build
flow.

**What holds either way:**

- The policy-path **map** is needed under both topologies, because the artifact's
  `commit_url` points at the monorepo regardless of the flow layout.
- The **map key** `template_reference_name` is robust to both: it is `web` under
  A (the only per-component identifier left) and under B (equals
  `flow_name[:-3]`). So that decision stands independent of the topology.
- Regardless of topology, make an *unrecognized* build flow **fail loud** (or warn
  into the job summary) rather than silently drop the running image. Silence is
  exactly what makes the skip dangerous, and a loud failure also protects against
  the topology changing under us later.

The topology is a doc 02-05 decision; this section just branches on it. It is now
pinned to **Topology B**, so implement the live-scan identity logic down the B
branch (the `*-ci`-style per-service flows survive and `flow_name[:-3]` keeps
working), after confirming the real services' per-service flow names.

### Determining whether a flow is a build flow (three options)

Separate from "which component" is "is this flow a *build* flow at all". The live
scan needs this because a fingerprint is attested to more than one flow: in the
live snapshot each scanned image appears in its `<component>-ci` build flow **and**
in `snyk-aws-beta-per-artifact` (the scan re-attests the artifact,
artifact_snyk_test.yml:423). The scan must pick the build flow (for its
`commit_url` and identity) and not double-process. There is **no explicit
build-ness marker in the snapshot** -- confirmed live: for `saver` the two
`flows[]` entries differ only by heuristic (`commit_url` -> `cyber-dojo/saver` and
a SHA `trail_name` for the build flow, vs `commit_url` -> `cyber-dojo/snyk-scanning`
and a `saver-<fingerprint>` `trail_name` for the scan flow). So build-ness is known
at attest time but lost by snapshot time. Three ways to recover it:

1. **Hardcoded `BUILD_FLOWS` allowlist** (today; artifacts.py:88-99). `snyk-scanning`
   has to know the name of every build flow. Fragile: it drifts as repos come and
   go, and it is exactly what produces the Topology-A silent-skip (the `monorepo`
   flow is not on the list, so its artifacts are dropped). No extra Kosli calls.
2. **Heuristic on snapshot fields** (e.g. "the flow whose `commit_url` is not
   `cyber-dojo/snyk-scanning`", or the SHA-shaped `trail_name`). No extra calls and
   no maintained list, but still a guess: a second non-build flow, or a monorepo
   `commit_url`, can fool it. Fragile in a different way.
3. **Annotate build-ness at attest time, read it back per flow (recommended).**
   Every `kosli attest artifact` call marks its `type` (`build` vs non-build) via
   an annotation -- the caller always knows which it is. The live scan then reads
   it with `kosli get artifact --fingerprint <fp> --flow <flow_name>`, iterating the
   snapshot's `flows[]` array. This removes the fragility outright: no allowlist to
   maintain, no heuristic, and it is **topology-independent** -- under Topology A
   the `monorepo` build attestation simply carries `type=build`, so there is no
   list to update and no silent-skip. Verified mechanics:
   - annotations are first-class on both write and read
     (`kosli-dev/.../models/artifacts.py:31` `CreateArtifact.annotations`, `:101`
     `ArtifactResponseBase.annotations`, inherited by the get-artifact
     `ArtifactResponse`, `:121`);
   - the snapshot enumerates **every** flow a fingerprint was attested to, each as
     its own `flows[]` entry with a non-null `flow_name` (verified across all 11
     aws-beta artifacts; 2-flow artifacts list both build and scan flows). So the
     per-flow `get artifact --flow` lookup is well-defined, and the same fingerprint
     annotated `type=build` in one flow and non-build in another is read flow by
     flow with no merged-dict collision. Drive these lookups off the `flows[]`
     array, never the artifact's top-level singular `flow_name`/`commit_url`, which
     collapse to a single representative flow.

   Cost: one `kosli get artifact` per (artifact, flow) -- roughly one to two per
   running image, a per-artifact round-trip the snapshot cannot avoid (unlike
   `template_reference_name`, which rides in the snapshot for free). The earlier
   "Kosli read-back is slow" note (artifacts.py:101-106) was about a `kosli get
   flow` per flow that was removed; this is a deliberate, accepted trade of a small
   number of calls for removing the allowlist fragility.

   Fail-safe requirement: an artifact whose build flow carries **no** `type`
   annotation (older images built before this rollout, mixed fleet) has unknown
   build-ness. Unknown must resolve to *scan it* (over-scan, safe) or *fail loud* --
   never *skip* -- otherwise the silent-skip returns by a different door. This is
   the inverse of today's allowlist default, where an unknown flow silently drops.

### Why the map file, and not provenance lookups

The map file holds the per-component `.snyk` *paths*; those paths cannot be
derived from anything in the snapshot, so they must be recorded somewhere
versioned with the code. A map file committed in the monorepo is that single
source of truth: read at the artifact's own commit, and free for the live path
because the snapshot already carries `commit_url` (artifacts.py:53).

Note this is separate from the *component key* used to index the map. We
originally worried that recovering a per-artifact value from Kosli would cost an
extra `kosli get attestation` round-trip (the kind the `is_build_flow` comment,
artifacts.py:101-106, says was deliberately removed). That worry does not apply
to the key: the snapshot already returns the component name per artifact (see
below), so indexing the map costs zero extra Kosli calls.

## The map file

Location: monorepo root, fetched at the artifact's commit (not the workflow's).
The workflow knows the name as a constant, alongside the existing
`SNYK_POLICY_FILENAME: .snyk`:

```
SNYK_POLICY_MAP_FILENAME: .snyk-policy-map.json
```

Shape:

```json
{
  "schema_version": 1,
  "policies": {
    "creator":   "source/creator/.snyk",
    "dashboard": "source/dashboard/.snyk",
    "web":       "source/web/.snyk",
    "differ":    null
  }
}
```

- Keys are component names, taken from the artifact's `template_reference_name`
  in the snapshot. This is the reference name the artifact was reported with at
  build time: `secure-docker-build.yml:219-221` runs
  `kosli attest artifact <image> --name ${kosli_reference_name}`, and each
  component sets `kosli_reference_name = service_name` (web/main.yml:99,
  creator/main.yml:132, dashboard/main.yml:141). So
  `template_reference_name == service_name == component`, set deliberately at the
  single source of truth (the build) and carried in provenance.

  The server already returns it per flow in the CLI snapshot response
  (`fastapi_app/models/snapshots.py:15`, `SnapshotArtifactFlow`), so the live and
  promotion paths read `flow["template_reference_name"]` from the build-flow entry
  they already iterate -- zero extra Kosli calls, no new attestation flag
  (`--annotate`/`--display-name` are not needed). In the build context the
  workflow already knows `service_name` directly as an input, so no snapshot is
  involved there.

  Confirmed live (point-in-time, not a standing test): a read-only
  `kosli get snapshot aws-beta --output=json` on 2026-06-13 (snapshot index 7180,
  type ECS, 11 artifacts) showed every build flow (`<component>-ci`) carrying a
  non-null `template_reference_name` equal to the component (creator-ci->creator,
  web-ci->web, dashboard-ci->dashboard, etc.). The per-artifact snyk flow
  (`snyk-aws-beta-per-artifact`, not in `BUILD_FLOWS`) also carried it, so the
  build flow is not the only source, and two concurrent `creator` versions both
  resolved to `creator`. Re-run the query to re-verify; the index will have moved
  on.

  Why this over the alternatives we considered:
  - Image-name basename (`${artifact_name##*/}` then strip tag/digest): works,
    but parses an OCI ref (flat-name assumption) and couples the key to image
    naming. `template_reference_name` is an explicit value, no parsing, and
    survives image renames.
  - `${KOSLI_ATTESTATION_NAME%%.*}` prefix: overloads a string whose job is
    naming the Kosli attestation slot; the convention already varies across
    callers (`web.snyk-container-scan` build/live vs `web.snyk-scan` promotion)
    and is set independently in ~10 caller repos.
  - `ecs_context.service_name` (`snapshots.py:52`) is also in the snapshot but is
    infra-derived and live-ECS-only (absent in build/promotion); useful at most
    as a cross-check, not the primary key.

  Fail-safe note: `template_reference_name` is optional. If a component does not
  set `kosli_reference_name` it is null, so the key is absent and the resolution
  table gives "root `.snyk` -> empty policy -> over-report" -- the safe,
  non-compliant-leaning direction that can never produce a false "compliant".
- String values are repo-root-relative paths to that component's `.snyk` file.
  Full file path (not a directory) so a component can name its file freely and
  creator's two source dirs (`app/`, `client/`) do not force a choice.
- `null` means the component deliberately has no policy: empty policy is
  intended, do not fail.
- `schema_version` lets the resolver refuse a shape it does not understand
  rather than misread it (fail toward non-compliance).

## Resolution rules

| Situation                                   | Action                                                        |
|---------------------------------------------|---------------------------------------------------------------|
| Map file absent at the commit               | Root `.snyk`; missing -> empty-policy fallback (today's behaviour). |
| Map present, component key absent           | Same as no map: root `.snyk`; missing -> empty-policy fallback. |
| Map present, key -> string path             | Declared. Fetch that path at the commit. Read fails -> fail loud (exit 1). |
| Map present, key -> `null`                  | Declared empty. Empty policy, no failure.                     |
| Map present, `schema_version` unknown       | Fail loud. Do not guess.                                      |

There is exactly one fail-loud trigger that matters: a component is explicitly
listed with a path and that path will not read. That is the genuine "you
declared a policy and it is broken" case.

### Generic reference names in non-monorepo repos (e.g. `artifact`)

The component key (`template_reference_name`) is only consulted when a map file
is present: the resolver fetches the map first, and with no map it never reads
the key at all (rows 1 and 2 above resolve to root `.snyk`). This matters for the
many repos that stay polyrepo and may use a generic reference name. A common
Kosli practice is to set `kosli_reference_name: artifact` (or similar) rather than
the component name, which makes that repo's `template_reference_name` come back as
`artifact`.

Such a repo (say `runner`, which is not becoming a monorepo) is fine as long as
either:

- it has no map file -- the key is never read, the resolver falls back to root
  `.snyk`, and runner's root `.snyk` is fetched correctly. Changing the reference
  name to `artifact` is then a complete no-op; or
- it has a map file keyed by whatever its `template_reference_name` actually is
  (`artifact`) -- the lookup hits and behaves as declared.

The only thing to avoid is a map keyed by a name that no longer matches the
reference name (e.g. a stale `runner` key while the reference name is now
`artifact`). Even that degrades safely rather than breaking: the lookup misses,
falls back to root `.snyk` (row 2), and for a polyrepo whose policy lives at root
the scan still works -- it just silently ignores the stale entry. The worst
outcome is empty-policy over-reporting, never a false "compliant".

Note this touches only the map key. On the polyrepo path (a repo like `runner`
that keeps its own `runner-ci` flow), changing `kosli_reference_name` does not
affect the rest of the pipeline: the live matrix still derives
`repo_name = flow_name[:-3]` (e.g. `runner` from `runner-ci`) and
`kosli_attestation_name = <repo_name>.snyk-container-scan` from the flow name,
both independent of the reference name. The monorepo path is different -- there
`flow_name` is `monorepo` and identity comes from `template_reference_name`
instead (under Topology A); see "Identifying the component in the live scan
depends on the monorepo flow topology" above.

Driving the absent-key vs null-value distinction in `jq`:

```bash
if jq -e --arg c "$COMPONENT" '.policies | has($c)' map.json >/dev/null; then
  PATH_VAL="$(jq -r --arg c "$COMPONENT" '.policies[$c] // "__NULL__"' map.json)"
  # "__NULL__" => declared-empty; otherwise => required path
else
  : # key absent => fall back to root .snyk
fi
```

This logic runs at both curl sites, so it must be one shared script the two
steps call, not copied logic that can drift.

## The input change to `artifact_snyk_test.yml`

Replace the `raw_snyk_policy_url` input with an optional `commit_url` input that
defaults to the github-context commit, then build the policy URL inside the
workflow after the map lookup.

- Build: input omitted; defaults to
  `${{github.server_url}}/${{github.repository}}/commit/${{github.sha}}`, which
  is correct because the build runs in the monorepo context. The artifact
  attestation also exists by then (`snyk-container-scan needs [build-image]`,
  and `build-image` attests via `secure-docker-build.yml`), but we do not need
  to query it because github context already has repo and sha.
- Live scan: `artifacts.py` passes `commit_url`, which it already extracts from
  the snapshot (artifacts.py:53), instead of building a `.snyk` URL. The
  `raw_snyk_policy_url()` function (artifacts.py:69-85) is then deleted.

This moves all policy-locating logic (read map, look up component, build the
`.snyk` URL) out of `artifacts.py` and the callers and into
`artifact_snyk_test.yml`, which is the right owner, while keeping the live path
at zero extra Kosli calls.

Fully eliminating the input (zero inputs) is possible by having the workflow
query the artifact attestation by fingerprint for its `commit_url`, but that
re-adds a per-artifact Kosli call in the live sweep for information the snapshot
already provides, so it is not recommended.

## Deliberate biases and an accepted gap

- Empty policy is the safe direction. An empty policy applies zero ignores, so
  more vulnerabilities are counted and the artifact is more likely flagged
  non-compliant. It can never produce a false "compliant", which respects the
  compliance asymmetry in `01-problem-and-goals.md`.
- Accepted gap: with "key absent -> root `.snyk`", a new component added to the
  monorepo but forgotten in the map scans with an empty policy and only a buried
  warning. This was chosen for leniency. The direction is safe (it over-reports,
  never under-reports). If we later want to close it, a cheap CI check that every
  `source/*/.snyk` has a matching map entry would catch the slip at source
  without changing this runtime behaviour.

## Open items for the next session

1. Confirm the `commit_url` input default format the workflow expects, and wire
   `artifacts.py` to pass `commit_url` through the matrix.
2. The monorepo flow topology is now settled as **Topology B** (per-component
   flows plus a `monorepo-co-deployment` binding flow; docs 02-05 are written to
   it), so take the Topology-B branch of item 3, after confirming the real
   services' per-service flow names (which decide `flow_name[:-3]`). The
   map-lookup **key** is `template_reference_name` either way; have `artifacts.py`
   read `flow["template_reference_name"]` and pass it through the matrix (same for
   `promotions.py`), and update the `snyk-scanning/tests/artifacts/*.snapshot.json`
   fixtures to include `template_reference_name` (the hand-built fixtures omit it).
   The build context passes its `service_name` directly.
3. Live-scan identity, conditional on item 2:
   - Under **Topology A**: make `is_build_flow`/`BUILD_FLOWS` (artifacts.py:88-106)
     recognize the `monorepo` flow so migrated components are not silently dropped,
     and take `repo_name` from `template_reference_name` (not `flow_name[:-3]`).
     Add a regression test that a `monorepo`-flow artifact produces a matrix entry.
   - Under **Topology B**: no identity change -- `web-ci` etc. survive and
     `flow_name[:-3]` keeps working; just keep the binding flow out of
     `BUILD_FLOWS`.
   - Either way: make an *unrecognized* build flow fail loud (or warn into the job
     summary) rather than silently omit the running image. A component scanned with
     no policy is the safe direction; a component never scanned at all is not.
4. Decide the build-ness mechanism (see "Determining whether a flow is a build
   flow"): keep the hardcoded `BUILD_FLOWS`, use a snapshot heuristic, or (preferred)
   annotate `type` at every `kosli attest artifact` and read it back per flow with
   `kosli get artifact --fingerprint <fp> --flow <flow_name>`. Option 3 removes the
   allowlist fragility and the Topology-A silent-skip and is topology-independent,
   but requires rolling out the attest-time annotation first and a fail-safe
   (scan-or-fail-loud, never skip) for artifacts built before the annotation
   existed. Confirm the `--annotate` flag spelling on `kosli attest artifact`.
5. Decide the map filename for real (`.snyk-policy-map.json` at root, or a
   non-dotfile, or under a `.cyber-dojo/` dir).
6. Write the shared resolution script and the fail-loud behaviour, then the
   tests that prove each row of the resolution table.
7. Decide whether to add the optional CI check for unlisted components.

## Key files and line references

- `snyk-scanning/.github/workflows/artifact_snyk_test.yml`
  - policy URL default: 77-81
  - empty `.snyk` then snyk run: 170-181
  - curl site 1 (find-snyk-vulns): 196-205
  - curl site 2 (attest-snyk-vulns): 408-415
  - `combine_snyk.py` call: 212-223
  - existing attestation-slot derivation (NOT the chosen key source): 422
  - attest gated to main: 53-57, 369
- `snyk-scanning/bin/combine_snyk.py`: policy read as YAML at 15, 54-55
- `snyk-scanning/bin/artifacts.py`
  - `commit_url` extracted from snapshot: 53
  - `repo_name = flow_name[:-3]` (polyrepo; also Topology B; breaks under Topology A): 54
  - `raw_snyk_policy_url()` root-`.snyk` builder to delete: 69-85
  - `BUILD_FLOWS` list (must also list `monorepo` under Topology A): 88-99
  - `is_build_flow` (the silent-skip gate under Topology A): 101-106
- monorepo flow topology (now Topology B; decides the live-scan identity logic):
  - `02-kosli-model.md` "Two tiers of flow" (per-service build flows plus the
    `monorepo-co-deployment` binding flow)
  - `03-ci-orchestration.md` "What each component workflow does" (each service
    runs its own flow, then attests its artifact into the binding trail)
  - `05-the-gate-policy.md` "Why one assertion on the binding trail's flag is
    enough" (the gate is one assertion on the binding trail's `is_compliant`)
- component key source (`template_reference_name = service_name`):
  - server CLI snapshot model: `kosli-dev/server/src/fastapi_app/models/snapshots.py:15` (`SnapshotArtifactFlow.template_reference_name`), `:52` (`ecs_context.service_name`)
  - attest with `--name`: `reusable-actions-workflows/.github/workflows/secure-docker-build.yml:219-221`
  - `kosli_reference_name = service_name`: web/main.yml:99, creator/main.yml:132, dashboard/main.yml:141
- build-ness via artifact annotation (option 3):
  - artifact annotations first-class on write + read: `kosli-dev/server/src/fastapi_app/models/artifacts.py:31` (`CreateArtifact.annotations`), `:101` (`ArtifactResponseBase.annotations`), `:121` (`ArtifactResponse`)
  - snapshot enumerates all flows per fingerprint (`flows[]`, each with `flow_name`): `snapshots.py:8` (`SnapshotArtifactFlow`), `:132` (`SnapshotArtifact.flows`)
  - artifact re-attested by the scan (the 2nd flow): `artifact_snyk_test.yml:423`
  - read-back: `kosli get artifact --fingerprint <fp> --flow <flow_name>` (docs.kosli.com/client_reference/kosli_get_artifact)
- `snyk-scanning/.github/workflows/env_snyk_test.yml`: matrix source 45, fan-out 49-66
- `snyk-scanning/.github/workflows/aws-beta.yml`: live scan entry, calls env_snyk_test at 62
- `creator/.github/workflows/main.yml`: snyk-container-scan job 138-149, build-image 119-135
