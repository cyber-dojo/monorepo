#!/usr/bin/env bash
# Tier 1 (per-service build flow), asymmetry / fail-CLOSED. Proves an UNEXPECTED
# attestation (one not declared in the service template) that is non-compliant
# STILL makes the artifact non-compliant, so the service's own gate (`kosli assert
# artifact`) DENIES. `unexpected: true` means "not required by the template", NOT
# "ignored for compliance": a known-bad ad-hoc attestation cannot be sneaked past
# the service gate (and so cannot reach the binding trail). [docs/02 `unexpected`]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "service unexpected-attestation commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
cgf=(--repo-root "${repo}" --commit "${sha}")
write_junit "${work}/reports"
printf 'artifact A for %s\n' "${flow}" > "${work}/A.bin"   # unique fingerprint per test

cat > "${work}/template.yml" <<'YML'
version: 1
trail:
  attestations:
    - { name: approval, type: generic }
  artifacts:
    - name: A
      attestations:
        - { name: lint, type: generic }
        - { name: unit-test, type: junit }
YML

echo "## arrange -- all required present+compliant, PLUS an unexpected A.surprise (--compliant=false)"
kosli_cli create flow "${flow}" --description "service unexpected attestation" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest generic --name approval --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest approval"
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact A"
kosli_cli attest generic --name A.lint --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.lint"
kosli_cli attest junit --name A.unit-test --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.unit-test"
kosli_cli attest generic --name A.surprise --compliant=false --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest unexpected A.surprise (not in template)"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
sel='.compliance_status.artifacts_statuses.A.attestations_statuses[]? | select(.attestation_name=="surprise")'
surprise_unexpected="$(json "${sel} | .unexpected")"
surprise_ic="$(json "${sel} | .is_compliant")"
echo "  OBSERVED A.surprise unexpected   = ${surprise_unexpected:-<absent>}"
echo "  OBSERVED A.surprise is_compliant = ${surprise_ic:-<absent>}"
echo "  OBSERVED A is_compliant          = ${a_ic}"

echo "## assert -- unexpected != ignored: a non-compliant unexpected attestation denies the self-check"
assert_equals "A.surprise flagged unexpected=true" "${surprise_unexpected}" "true"
assert_equals "A.surprise is non-compliant"        "${surprise_ic}" "false"
assert_equals "artifact A NOT compliant (unexpected evidence still counts)" "${a_ic}" "false"
kosli_cli assert artifact "${work}/A.bin" --artifact-type file --flow "${flow}"
assert_exit_nonzero "kosli assert artifact (the service self-check) DENIES"

finish
