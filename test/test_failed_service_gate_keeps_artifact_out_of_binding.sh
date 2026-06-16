#!/usr/bin/env bash
# Tier 3 (cross-tier, the heart of the design). Proves the evaluate-then-bind
# invariant end to end: the orchestrator binds a service's artifact into the
# binding trail ONLY AFTER the service passes its own gate. web is fully compliant in
# its own flow, so its gate passes and web is bound into the binding trail. dashboard is
# missing an attestation in its own flow, so its gate FAILS and -- mirroring the
# bind-X job (evaluate, then attest) -- dashboard is never bound into the binding trail.
# The binding trail then has web present and dashboard MISSING, so the whole-commit gate
# DENIES. This is the trust boundary in docs/06: the whole-commit gate never
# re-verifies dashboard's evidence; it relies on dashboard never being bound.
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

base="$(basename "$0" .sh | tr '_' '-')"
svcweb="${base}-svc-web"       # web's own build flow
svcdashboard="${base}-svc-dashboard"       # dashboard's own build flow
binding="${base}-binding"  # the monorepo-co-deployment-style binding flow
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "cross-tier commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
cgf=(--repo-root "${repo}" --commit "${sha}")
write_junit "${work}/reports"
printf 'artifact web for %s\n' "${base}" > "${work}/web.bin"   # distinct fingerprints
printf 'artifact dashboard for %s\n' "${base}" > "${work}/dashboard.bin"

# Each service flow: trail-level approval + artifact {lint, unit-test}.
cat > "${work}/svc.yml" <<'YML'
version: 1
trail:
  attestations:
    - { name: approval, type: generic }
  artifacts:
    - name: ART
      attestations:
        - { name: lint, type: generic }
        - { name: unit-test, type: junit }
YML
sed 's/ART/web/' "${work}/svc.yml" > "${work}/svcweb.yml"
sed 's/ART/dashboard/' "${work}/svc.yml" > "${work}/svcdashboard.yml"

# Binding template scoped to {web,dashboard}: both are expected this commit.
"${root}/bin/scoped-template" --repo-root "${root}" '["web","dashboard"]' > "${work}/binding.yml"

echo "## arrange service flows -- web fully compliant; dashboard missing dashboard.unit-test"
kosli_cli create flow "${svcweb}" --description "service web" --template-file "${work}/svcweb.yml"
assert_exit_zero "create flow svc-web"
kosli_cli create flow "${svcdashboard}" --description "service dashboard" --template-file "${work}/svcdashboard.yml"
assert_exit_zero "create flow svc-dashboard"
kosli_cli begin trail "${trail}" --flow "${svcweb}"; assert_exit_zero "begin trail svc-web"
kosli_cli begin trail "${trail}" --flow "${svcdashboard}"; assert_exit_zero "begin trail svc-dashboard"
# web: complete and compliant
kosli_cli attest generic --name approval --compliant=true --flow "${svcweb}" --trail "${trail}" "${cgf[@]}";  assert_exit_zero "web approval"
kosli_cli attest artifact "${work}/web.bin" --artifact-type file --name web --flow "${svcweb}" --trail "${trail}" "${agf[@]}"; assert_exit_zero "web artifact"
kosli_cli attest generic --name web.lint --compliant=true --flow "${svcweb}" --trail "${trail}" "${cgf[@]}"; assert_exit_zero "web.lint"
kosli_cli attest junit --name web.unit-test --results-dir "${work}/reports" --flow "${svcweb}" --trail "${trail}" "${cgf[@]}"; assert_exit_zero "web.unit-test"
# dashboard: approval + artifact + lint, but dashboard.unit-test omitted -> dashboard non-compliant in its own flow
kosli_cli attest generic --name approval --compliant=true --flow "${svcdashboard}" --trail "${trail}" "${cgf[@]}";  assert_exit_zero "dashboard approval"
kosli_cli attest artifact "${work}/dashboard.bin" --artifact-type file --name dashboard --flow "${svcdashboard}" --trail "${trail}" "${agf[@]}"; assert_exit_zero "dashboard artifact"
kosli_cli attest generic --name dashboard.lint --compliant=true --flow "${svcdashboard}" --trail "${trail}" "${cgf[@]}"; assert_exit_zero "dashboard.lint"

echo "## the binding flow for this commit"
kosli_cli create flow "${binding}" --description "binding" --template-file "${work}/binding.yml"; assert_exit_zero "create binding flow"
kosli_cli begin trail "${trail}" --flow "${binding}"; assert_exit_zero "begin binding trail"

echo "## act -- the orchestrator gates each service flow, then binds ONLY if it passed"
kosli_cli evaluate trail "${trail}" --flow "${svcweb}" --policy "${root}/policy/component.rego" --assert
assert_exit_zero "web per-service gate PASSES"
a_gate="${_status}"
kosli_cli evaluate trail "${trail}" --flow "${svcdashboard}" --policy "${root}/policy/component.rego" --assert
assert_exit_nonzero "dashboard per-service gate FAILS"
b_gate="${_status}"

# Mirror the bind-X job's evaluate-then-attest ordering: bind into the binding trail
# only on a passing per-service gate. web passed (so it is bound); dashboard failed (so it is
# never bound). The orchestrator binds by --fingerprint; attesting the same file
# here yields the identical artifact identity.
if [ "${a_gate}" -eq 0 ]; then
  kosli_cli attest artifact "${work}/web.bin" --artifact-type file --name web --flow "${binding}" --trail "${trail}" "${agf[@]}"
  assert_exit_zero "web attests into binding trail (passed its gate)"
fi
_checks=$((_checks + 1))
if [ "${b_gate}" -eq 0 ]; then
  kosli_cli attest artifact "${work}/dashboard.bin" --artifact-type file --name dashboard --flow "${binding}" --trail "${trail}" "${agf[@]}"
  _fail "dashboard must NOT have attested into the binding trail"
else
  _pass "dashboard does NOT attest into binding trail (failed its gate)"
fi

echo "## assert -- binding has web present, dashboard MISSING => whole-commit gate denies"
kosli_cli get trail "${trail}" --flow "${binding}" --output json
assert_exit_zero "get binding trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
web_ic="$(json '.compliance_status.artifacts_statuses.web.is_compliant')"
dashboard_status="$(json '.compliance_status.artifacts_statuses.dashboard.status // "<absent>"')"
echo "  OBSERVED binding is_compliant = ${trail_ic} (web=${web_ic}, dashboard status=${dashboard_status})"
assert_equals "web present+compliant in binding" "${web_ic}" "true"
assert_equals "dashboard MISSING in binding (its failed gate kept it out)" "${dashboard_status}" "MISSING"
assert_equals "binding trail NOT compliant" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${binding}" --policy "${root}/policy/gate.rego" --assert
assert_exit_nonzero "gate.rego DENIES the whole commit"

finish
