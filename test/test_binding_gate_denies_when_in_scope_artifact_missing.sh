#!/usr/bin/env bash
# Tier 2 (binding trail), the central tie-together claim, negative direction.
# Proves that if a component is in scope for the commit but its artifact is absent
# from the binding trail -- whether because it failed its own gate and never
# attested, or never ran at all -- the whole-commit gate DENIES. The binding
# template lists {A,B}; only A attests; B is left MISSING. Under the binding model
# "B failed" and "B never ran" are the same MISSING artifact, so this single test
# covers both the old two_components_one_not_compliant and the old
# in_scope_artifact_never_reported. [docs/01 "silence is never success", docs/06]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated binding flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "binding missing-artifact commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
printf 'artifact A for %s\n' "${flow}" > "${work}/A.bin"   # unique fingerprint per test

# Binding template scoped to {A,B}: both are expected this commit.
"${root}/bin/scoped-template" --repo-root "${root}" '["A","B"]' > "${work}/template.yml"

echo "## arrange -- only A attests into the binding trail; B never does"
kosli_cli create flow "${flow}" --description "binding missing artifact" --template-file "${work}/template.yml"
assert_exit_zero "create binding flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact A into binding trail"
# B deliberately NEVER attested (it failed its own gate, or never ran).

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
b_present="$(json '.compliance_status.artifacts_statuses | has("B")')"
b_status="$(json '.compliance_status.artifacts_statuses.B.status // "<absent>"')"
echo "  OBSERVED binding is_compliant = ${trail_ic} (A=${a_ic})"
echo "  OBSERVED artifacts_statuses.B present = ${b_present} (status=${b_status})"

echo "## assert -- an in-scope artifact left out => binding non-compliant + gate denies"
assert_equals "A present+compliant" "${a_ic}" "true"
assert_equals "expected B listed as MISSING (not omitted)" "${b_status}" "MISSING"
assert_equals "binding trail NOT compliant" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_nonzero "gate.rego DENIES the binding trail"

finish
