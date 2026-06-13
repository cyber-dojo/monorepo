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

### Why the map file, and not provenance lookups

We checked what a Kosli environment snapshot exposes per artifact:

```
annotation, fingerprint, name, flows[].{commit_url, flow_name, git_commit}
```

No attestations or annotations are in the snapshot. So recording the path on
either the artifact attestation or the snyk-scan attestation and reading it back
would cost an extra per-artifact `kosli get attestation` call. That is exactly
the slow per-artifact Kosli round-trip the `is_build_flow` comment
(artifacts.py:101-106) says was deliberately removed.

A map file committed in the monorepo avoids all of that. It is a single source
of truth, versioned with the code, read at the artifact's own commit, and the
component key it needs (`creator`) is already available cheaply from the
attestation name (see below). It also stays free for the live path because the
snapshot already carries `commit_url` (artifacts.py:53).

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

- Keys are component / artifact-slot names. The workflow already derives this
  cheaply at artifact_snyk_test.yml:422:
  `ARTIFACT_SLOT_NAME="${KOSLI_ATTESTATION_NAME%%.*}"`, for example
  `creator.snyk-container-scan` -> `creator`. `kosli_attestation_name` is passed
  in both contexts (build: `creator.snyk-container-scan`; live:
  `${{matrix.repo_name}}.snyk-container-scan`). No new input is needed to index
  the map.
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
2. Decide the map filename for real (`.snyk-policy-map.json` at root, or a
   non-dotfile, or under a `.cyber-dojo/` dir).
3. Write the shared resolution script and the fail-loud behaviour, then the
   tests that prove each row of the resolution table.
4. Decide whether to add the optional CI check for unlisted components.

## Key files and line references

- `snyk-scanning/.github/workflows/artifact_snyk_test.yml`
  - policy URL default: 77-81
  - empty `.snyk` then snyk run: 170-181
  - curl site 1 (find-snyk-vulns): 196-205
  - curl site 2 (attest-snyk-vulns): 408-415
  - `combine_snyk.py` call: 212-223
  - component-slot derivation: 422
  - attest gated to main: 53-57, 369
- `snyk-scanning/bin/combine_snyk.py`: policy read as YAML at 15, 54-55
- `snyk-scanning/bin/artifacts.py`
  - `commit_url` extracted from snapshot: 53
  - `repo_name = flow_name[:-3]`: 54
  - `raw_snyk_policy_url()` root-`.snyk` builder to delete: 69-85
  - `BUILD_FLOWS` list: 88-99
- `snyk-scanning/.github/workflows/env_snyk_test.yml`: matrix source 45, fan-out 49-66
- `snyk-scanning/.github/workflows/aws-beta.yml`: live scan entry, calls env_snyk_test at 62
- `creator/.github/workflows/main.yml`: snyk-container-scan job 138-149, build-image 119-135
