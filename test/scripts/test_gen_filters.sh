#!/usr/bin/env bash
# Proves bin/gen-filters derives the dorny/paths-filter rules from the fragment
# files. Each source/<X>/kosli.yml yields a filter that watches THREE things:
#   * the component's source tree     source/X/**
#   * the component's own pipeline     .github/workflows/x.yml   (lowercased)
#   * the shared orchestration infra   main.yml, the bin/ generators,
#     kosli/trail.yml, policy/gate.rego
# so that editing a component's workflow, or any shared infra, rebuilds it.
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
source "${here}/../assert.sh"

out="$("${root}/bin/gen-filters" --repo-root "${root}")"
printf '%s\n' "${out}" | sed 's/^/  filters: /'

line_for() { printf '%s\n' "${out}" | grep "^$1:"; }

a="$(line_for A)"
assert_contains     "A watches its source tree"        "${a}" "source/A/**"
assert_contains     "A watches its own workflow"       "${a}" ".github/workflows/a.yml"
assert_not_contains "A does not watch B's workflow"    "${a}" "workflows/b.yml"
assert_contains     "A watches shared orchestrator"    "${a}" ".github/workflows/main.yml"
assert_contains     "A watches shared gen-filters"     "${a}" "bin/gen-filters"
assert_contains     "A watches shared scoped-template" "${a}" "bin/scoped-template"
assert_contains     "A watches shared trail skeleton"  "${a}" "kosli/trail.yml"
assert_contains     "A watches shared gate policy"     "${a}" "policy/gate.rego"

b="$(line_for B)"
assert_contains "B watches its source tree"  "${b}" "source/B/**"
assert_contains "B watches its own workflow" "${b}" ".github/workflows/b.yml"
assert_contains "B watches shared gate"      "${b}" "policy/gate.rego"

c="$(line_for C)"
assert_contains "C watches its source tree"  "${c}" "source/C/**"
assert_contains "C watches its own workflow" "${c}" ".github/workflows/c.yml"
assert_contains "C watches shared gate"      "${c}" "policy/gate.rego"

finish
