#!/usr/bin/env bash
# Tier 2 (binding trail), per-commit scoping. Proves a binding trail scoped to a
# SUBSET is compliant on its own: a commit that legitimately built only web expects
# only web. The binding template lists just {web} (dashboard and creator not in scope), web attests,
# and the gate ALLOWS without dashboard or creator being present. This is what lets the gate be
# a single positive assertion: components not in the scoped template are not
# required. [docs/02 per-commit scoping, docs/05]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated binding flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "binding scoped-subset commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
printf 'artifact web for %s\n' "${flow}" > "${work}/web.bin"   # unique fingerprint per test

# Binding template scoped to {web} only: dashboard and creator are NOT expected this commit.
"${root}/bin/scoped-template" --repo-root "${root}" '["web"]' > "${work}/template.yml"

echo "## arrange -- only web is in scope, and web attests into the binding trail"
kosli_cli create flow "${flow}" --description "binding scoped subset" --template-file "${work}/template.yml"
assert_exit_zero "create binding flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest artifact "${work}/web.bin" --artifact-type file --name web --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact web into binding trail"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
web_ic="$(json '.compliance_status.artifacts_statuses.web.is_compliant')"
dashboard_present="$(json '.compliance_status.artifacts_statuses | has("dashboard")')"
echo "  OBSERVED binding is_compliant = ${trail_ic} (web=${web_ic}, dashboard present=${dashboard_present})"

echo "## assert -- subset scope is compliant on its own => gate allows"
assert_equals "web present+compliant" "${web_ic}" "true"
assert_equals "dashboard not in the scoped binding template" "${dashboard_present}" "false"
assert_equals "binding trail compliant with just web" "${trail_ic}" "true"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_zero "gate.rego ALLOWS the subset-scoped binding trail"

finish
