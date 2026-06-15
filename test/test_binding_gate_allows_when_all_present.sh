#!/usr/bin/env bash
# Tier 2 (binding trail), positive control. Proves the whole-commit gate over the
# monorepo-co-deployment trail ALLOWS when every in-scope component is present in
# the binding set. The binding template (from bin/scoped-template) lists BARE
# artifacts {A,B} with no attestations; A and B each attest their artifact (as a
# service does post-gate). A bare artifact that is present is compliant, so the
# binding trail is compliant and gate.rego allows. This is the positive control
# for the AND in test_binding_gate_denies_when_in_scope_artifact_missing.sh.
# [docs/02 binding flow, docs/05 allow-when-compliant]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated binding flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "binding all-present commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
printf 'artifact A for %s\n' "${flow}" > "${work}/A.bin"   # unique fingerprints per test
printf 'artifact B for %s\n' "${flow}" > "${work}/B.bin"

# The real generated binding template: bare artifacts for the in-scope components.
"${root}/bin/scoped-template" --repo-root "${root}" '["A","B"]' > "${work}/template.yml"

echo "## arrange -- bare A and B both attested into the binding trail"
kosli_cli create flow "${flow}" --description "binding all present" --template-file "${work}/template.yml"
assert_exit_zero "create binding flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact A into binding trail"
kosli_cli attest artifact "${work}/B.bin" --artifact-type file --name B --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact B into binding trail"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
b_ic="$(json '.compliance_status.artifacts_statuses.B.is_compliant')"
echo "  OBSERVED binding is_compliant = ${trail_ic} (A=${a_ic}, B=${b_ic})"

echo "## assert -- every in-scope artifact present => binding compliant + gate allows"
assert_equals "bare artifact A present+compliant" "${a_ic}" "true"
assert_equals "bare artifact B present+compliant" "${b_ic}" "true"
assert_equals "binding trail compliant" "${trail_ic}" "true"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_zero "gate.rego ALLOWS the compliant binding trail"

finish
