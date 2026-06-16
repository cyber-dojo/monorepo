#!/usr/bin/env bash
# Proves bin/gen-filters derives the dorny/paths-filter rules from the fragment
# files. Each source/<X>/kosli.yml yields a filter that watches THREE things:
#   * the component's source tree     source/X/**
#   * the component's own pipeline     .github/workflows/x.yml   (lowercased)
#   * the shared orchestration infra   main.yml, the bin/ generators,
#     the policy/ directory (policy/**)
# so that editing a component's workflow, or any shared infra, rebuilds it.
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
source "${here}/../assert.sh"

out="$("${root}/bin/gen-filters" --repo-root "${root}")"
printf '%s\n' "${out}" | sed 's/^/  filters: /'

line_for() { printf '%s\n' "${out}" | grep "^$1:"; }

web="$(line_for web)"
assert_contains     "web watches its source tree"        "${web}" "source/web/**"
assert_contains     "web watches its own workflow"       "${web}" ".github/workflows/web.yml"
assert_not_contains "web does not watch dashboard's workflow" "${web}" "workflows/dashboard.yml"
assert_contains     "web watches shared orchestrator"    "${web}" ".github/workflows/main.yml"
assert_contains     "web watches shared gen-filters"     "${web}" "bin/gen-filters"
assert_contains     "web watches shared scoped-template" "${web}" "bin/scoped-template"
assert_contains     "web watches the shared policy dir"  "${web}" "policy/**"
assert_not_contains "web no longer watches removed trail skeleton" "${web}" "kosli/trail.yml"

dashboard="$(line_for dashboard)"
assert_contains "dashboard watches its source tree"  "${dashboard}" "source/dashboard/**"
assert_contains "dashboard watches its own workflow" "${dashboard}" ".github/workflows/dashboard.yml"
assert_contains "dashboard watches the shared policy dir" "${dashboard}" "policy/**"

creator="$(line_for creator)"
assert_contains "creator watches its source tree"  "${creator}" "source/creator/**"
assert_contains "creator watches its own workflow" "${creator}" ".github/workflows/creator.yml"
assert_contains "creator watches the shared policy dir" "${creator}" "policy/**"

finish
