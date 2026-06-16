#!/usr/bin/env bash
# Tier 2 (binding trail), positive control. Proves the whole-commit gate over the
# monorepo-co-deployment trail ALLOWS when every in-scope component is present in
# the binding set. The binding template (from bin/scoped-template) lists BARE
# artifacts {web,dashboard} with no attestations; web and dashboard each attest their artifact (as a
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
printf 'artifact web for %s\n' "${flow}" > "${work}/web.bin"   # unique fingerprints per test
printf 'artifact dashboard for %s\n' "${flow}" > "${work}/dashboard.bin"

# The real generated binding template: bare artifacts for the in-scope components.
"${root}/bin/scoped-template" --repo-root "${root}" '["web","dashboard"]' > "${work}/template.yml"

echo "## arrange -- bare web and dashboard both attested into the binding trail"
kosli_cli create flow "${flow}" --description "binding all present" --template-file "${work}/template.yml"
assert_exit_zero "create binding flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest artifact "${work}/web.bin" --artifact-type file --name web --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact web into binding trail"
kosli_cli attest artifact "${work}/dashboard.bin" --artifact-type file --name dashboard --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact dashboard into binding trail"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
web_ic="$(json '.compliance_status.artifacts_statuses.web.is_compliant')"
dashboard_ic="$(json '.compliance_status.artifacts_statuses.dashboard.is_compliant')"
echo "  OBSERVED binding is_compliant = ${trail_ic} (web=${web_ic}, dashboard=${dashboard_ic})"

echo "## assert -- every in-scope artifact present => binding compliant + gate allows"
assert_equals "bare artifact web present+compliant" "${web_ic}" "true"
assert_equals "bare artifact dashboard present+compliant" "${dashboard_ic}" "true"
assert_equals "binding trail compliant" "${trail_ic}" "true"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_zero "gate.rego ALLOWS the compliant binding trail"

finish
