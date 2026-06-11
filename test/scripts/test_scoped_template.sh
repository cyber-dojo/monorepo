#!/usr/bin/env bash
# Proves bin/scoped-template composes the per-commit template as a strict SUBSET
# of the fragments: the shared trail-level attestations always, plus exactly the
# changed components' artifact entries (verbatim), and nothing else. [docs/04]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
source "${here}/../assert.sh"

st() { "${root}/bin/scoped-template" --repo-root "${root}" "$1"; }

echo "## A and B changed -> A and B only"
out="$(st '["A","B"]')"
assert_contains     "trail-level pull-request kept" "${out}" "pull-request"
assert_contains     "artifact A present"            "${out}" "- name: A"
assert_contains     "artifact B present"            "${out}" "- name: B"
assert_not_contains "artifact C absent"             "${out}" "- name: C"

echo "## only A changed -> A only"
out="$(st '["A"]')"
assert_contains     "artifact A present" "${out}" "- name: A"
assert_not_contains "artifact B absent"  "${out}" "- name: B"
assert_not_contains "artifact C absent"  "${out}" "- name: C"

echo "## nothing changed -> trail-level only, no artifacts"
out="$(st '[]')"
assert_contains     "trail-level still present" "${out}" "pull-request"
assert_not_contains "no artifact A"             "${out}" "- name: A"

echo "## subset, not re-authored: A's fragment attestations appear verbatim"
out="$(st '["A"]')"
assert_contains "A.lint declared"      "${out}" "lint"
assert_contains "A.unit-test declared" "${out}" "unit-test"

finish
