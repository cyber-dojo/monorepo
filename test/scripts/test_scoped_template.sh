#!/usr/bin/env bash
# Proves bin/scoped-template composes the monorepo-co-deployment BINDING template:
# exactly one BARE artifact per in-scope component (no trail-level attestations and
# no per-artifact attestations -- that evidence lives in each service's own flow),
# nothing for out-of-scope components, and a fail-loud on an unknown component so
# it is never silently dropped from the co-deployment set. [docs/04]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
source "${here}/../assert.sh"

st() { "${root}/bin/scoped-template" --repo-root "${root}" "$1"; }

echo "## A and B in scope -> bare A and B only"
out="$(st '["A","B"]')"
assert_contains     "artifact A present" "${out}" "- name: A"
assert_contains     "artifact B present" "${out}" "- name: B"
assert_not_contains "artifact C absent"  "${out}" "- name: C"

echo "## the binding template carries NO attestations"
assert_not_contains "no trail-level pull-request"      "${out}" "pull-request"
assert_not_contains "no attestations block at all"     "${out}" "attestations"
assert_not_contains "no lint attestation"              "${out}" "lint"
assert_not_contains "no unit-test attestation"         "${out}" "unit-test"

echo "## only A in scope -> A only"
out="$(st '["A"]')"
assert_contains     "artifact A present" "${out}" "- name: A"
assert_not_contains "artifact B absent"  "${out}" "- name: B"
assert_not_contains "artifact C absent"  "${out}" "- name: C"

echo "## nothing in scope -> empty artifact list, still valid template"
out="$(st '[]')"
assert_contains     "trail.artifacts key present" "${out}" "artifacts"
assert_not_contains "no artifact A"               "${out}" "- name: A"

echo "## all three in scope -> exactly three bare artifacts"
out="$(st '["A","B","C"]')"
count="$(printf '%s\n' "${out}" | grep -c -- "- name: " || true)"
assert_equals   "exactly three artifact entries" "${count}" "3"
assert_contains "artifact A present" "${out}" "- name: A"
assert_contains "artifact B present" "${out}" "- name: B"
assert_contains "artifact C present" "${out}" "- name: C"

echo "## an unknown component fails loud (never silently dropped from the set)"
_checks=$((_checks + 1))
if "${root}/bin/scoped-template" --repo-root "${root}" '["A","Z"]' >/dev/null 2>&1; then
  _fail "bogus component should exit non-zero"
else
  _pass "bogus component fails loud"
fi

finish
