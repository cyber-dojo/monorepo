#!/usr/bin/env bash
# Tier 3 (cross-tier, the heart of the design). Proves the evaluate-then-bind
# invariant end to end: the orchestrator binds a service's artifact into the
# binding trail ONLY AFTER the service passes its own gate. A is fully compliant in
# its own flow, so its gate passes and A is bound into the binding trail. B is
# missing an attestation in its own flow, so its gate FAILS and -- mirroring the
# bind-X job (evaluate, then attest) -- B is never bound into the binding trail.
# The binding trail then has A present and B MISSING, so the whole-commit gate
# DENIES. This is the trust boundary in docs/06: the whole-commit gate never
# re-verifies B's evidence; it relies on B never being bound.
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

base="$(basename "$0" .sh | tr '_' '-')"
svca="${base}-svc-a"       # A's own build flow
svcb="${base}-svc-b"       # B's own build flow
binding="${base}-binding"  # the monorepo-co-deployment-style binding flow
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "cross-tier commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
cgf=(--repo-root "${repo}" --commit "${sha}")
write_junit "${work}/reports"
printf 'artifact A for %s\n' "${base}" > "${work}/A.bin"   # distinct fingerprints
printf 'artifact B for %s\n' "${base}" > "${work}/B.bin"

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
sed 's/ART/A/' "${work}/svc.yml" > "${work}/svca.yml"
sed 's/ART/B/' "${work}/svc.yml" > "${work}/svcb.yml"

# Binding template scoped to {A,B}: both are expected this commit.
"${root}/bin/scoped-template" --repo-root "${root}" '["A","B"]' > "${work}/binding.yml"

echo "## arrange service flows -- A fully compliant; B missing B.unit-test"
kosli_cli create flow "${svca}" --description "service A" --template-file "${work}/svca.yml"
assert_exit_zero "create flow svc-a"
kosli_cli create flow "${svcb}" --description "service B" --template-file "${work}/svcb.yml"
assert_exit_zero "create flow svc-b"
kosli_cli begin trail "${trail}" --flow "${svca}"; assert_exit_zero "begin trail svc-a"
kosli_cli begin trail "${trail}" --flow "${svcb}"; assert_exit_zero "begin trail svc-b"
# A: complete and compliant
kosli_cli attest generic --name approval --compliant=true --flow "${svca}" --trail "${trail}" "${cgf[@]}";  assert_exit_zero "A approval"
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${svca}" --trail "${trail}" "${agf[@]}"; assert_exit_zero "A artifact"
kosli_cli attest generic --name A.lint --compliant=true --flow "${svca}" --trail "${trail}" "${cgf[@]}"; assert_exit_zero "A.lint"
kosli_cli attest junit --name A.unit-test --results-dir "${work}/reports" --flow "${svca}" --trail "${trail}" "${cgf[@]}"; assert_exit_zero "A.unit-test"
# B: approval + artifact + lint, but B.unit-test omitted -> B non-compliant in its own flow
kosli_cli attest generic --name approval --compliant=true --flow "${svcb}" --trail "${trail}" "${cgf[@]}";  assert_exit_zero "B approval"
kosli_cli attest artifact "${work}/B.bin" --artifact-type file --name B --flow "${svcb}" --trail "${trail}" "${agf[@]}"; assert_exit_zero "B artifact"
kosli_cli attest generic --name B.lint --compliant=true --flow "${svcb}" --trail "${trail}" "${cgf[@]}"; assert_exit_zero "B.lint"

echo "## the binding flow for this commit"
kosli_cli create flow "${binding}" --description "binding" --template-file "${work}/binding.yml"; assert_exit_zero "create binding flow"
kosli_cli begin trail "${trail}" --flow "${binding}"; assert_exit_zero "begin binding trail"

echo "## act -- the orchestrator gates each service flow, then binds ONLY if it passed"
kosli_cli evaluate trail "${trail}" --flow "${svca}" --policy "${root}/policy/component.rego" --assert
assert_exit_zero "A per-service gate PASSES"
a_gate="${_status}"
kosli_cli evaluate trail "${trail}" --flow "${svcb}" --policy "${root}/policy/component.rego" --assert
assert_exit_nonzero "B per-service gate FAILS"
b_gate="${_status}"

# Mirror the bind-X job's evaluate-then-attest ordering: bind into the binding trail
# only on a passing per-service gate. A passed (so it is bound); B failed (so it is
# never bound). The orchestrator binds by --fingerprint; attesting the same file
# here yields the identical artifact identity.
if [ "${a_gate}" -eq 0 ]; then
  kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${binding}" --trail "${trail}" "${agf[@]}"
  assert_exit_zero "A attests into binding trail (passed its gate)"
fi
_checks=$((_checks + 1))
if [ "${b_gate}" -eq 0 ]; then
  kosli_cli attest artifact "${work}/B.bin" --artifact-type file --name B --flow "${binding}" --trail "${trail}" "${agf[@]}"
  _fail "B must NOT have attested into the binding trail"
else
  _pass "B does NOT attest into binding trail (failed its gate)"
fi

echo "## assert -- binding has A present, B MISSING => whole-commit gate denies"
kosli_cli get trail "${trail}" --flow "${binding}" --output json
assert_exit_zero "get binding trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
b_status="$(json '.compliance_status.artifacts_statuses.B.status // "<absent>"')"
echo "  OBSERVED binding is_compliant = ${trail_ic} (A=${a_ic}, B status=${b_status})"
assert_equals "A present+compliant in binding" "${a_ic}" "true"
assert_equals "B MISSING in binding (its failed gate kept it out)" "${b_status}" "MISSING"
assert_equals "binding trail NOT compliant" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${binding}" --policy "${root}/policy/gate.rego" --assert
assert_exit_nonzero "gate.rego DENIES the whole commit"

finish
