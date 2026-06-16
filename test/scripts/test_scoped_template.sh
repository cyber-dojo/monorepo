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

echo "## web and dashboard in scope -> bare web and dashboard only"
out="$(st '["web","dashboard"]')"
assert_contains     "artifact web present"       "${out}" "- name: web"
assert_contains     "artifact dashboard present" "${out}" "- name: dashboard"
assert_not_contains "artifact creator absent"    "${out}" "- name: creator"

echo "## the binding template carries NO attestations"
assert_not_contains "no trail-level pull-request"      "${out}" "pull-request"
assert_not_contains "no attestations block at all"     "${out}" "attestations"
assert_not_contains "no lint attestation"              "${out}" "lint"
assert_not_contains "no unit-test attestation"         "${out}" "unit-test"

echo "## only web in scope -> web only"
out="$(st '["web"]')"
assert_contains     "artifact web present"       "${out}" "- name: web"
assert_not_contains "artifact dashboard absent"  "${out}" "- name: dashboard"
assert_not_contains "artifact creator absent"    "${out}" "- name: creator"

echo "## nothing in scope -> empty artifact list, still valid template"
out="$(st '[]')"
assert_contains     "trail.artifacts key present" "${out}" "artifacts"
assert_not_contains "no artifact web"             "${out}" "- name: web"

echo "## all three in scope -> exactly three bare artifacts"
out="$(st '["web","dashboard","creator"]')"
count="$(printf '%s\n' "${out}" | grep -c -- "- name: " || true)"
assert_equals   "exactly three artifact entries" "${count}" "3"
assert_contains "artifact web present"       "${out}" "- name: web"
assert_contains "artifact dashboard present" "${out}" "- name: dashboard"
assert_contains "artifact creator present"   "${out}" "- name: creator"

echo "## an unknown component fails loud (never silently dropped from the set)"
_checks=$((_checks + 1))
if "${root}/bin/scoped-template" --repo-root "${root}" '["web","Z"]' >/dev/null 2>&1; then
  _fail "bogus component should exit non-zero"
else
  _pass "bogus component fails loud"
fi

finish
