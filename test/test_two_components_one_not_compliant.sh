#!/usr/bin/env bash
# Proves the central "tie compliance together" claim, negative direction: with a
# scoped template of two components {A,B} that share no attestation, if A is fully
# compliant but B is missing an attestation, the WHOLE commit is non-compliant and
# the gate denies. One bad in-scope component fails the lot.
# [docs/01 "compliant iff every component it should have built is compliant"]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "two-components-one-bad commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
cgf=(--repo-root "${repo}" --commit "${sha}")
write_junit "${work}/reports"
printf 'artifact A for %s\n' "${flow}" > "${work}/A.bin"   # unique fingerprints per test
printf 'artifact B for %s\n' "${flow}" > "${work}/B.bin"

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
    - name: B
      attestations:
        - { name: rubocop, type: junit }
        - { name: snyk-container-scan, type: generic }
YML

echo "## arrange -- A fully attested; B missing snyk-container-scan"
kosli_cli create flow "${flow}" --description "two components, one bad" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest generic --name approval --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest approval"
# A: complete and compliant
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact A"
kosli_cli attest generic --name A.lint --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.lint"
kosli_cli attest junit --name A.unit-test --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.unit-test"
# B: artifact + rubocop only; snyk-container-scan deliberately omitted
kosli_cli attest artifact "${work}/B.bin" --artifact-type file --name B --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact B"
kosli_cli attest junit --name B.rubocop --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest B.rubocop"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
b_ic="$(json '.compliance_status.artifacts_statuses.B.is_compliant')"
echo "  OBSERVED trail is_compliant = ${trail_ic} (A=${a_ic}, B=${b_ic})"

echo "## assert -- one non-compliant in-scope component fails the whole commit"
assert_equals "A is compliant" "${a_ic}" "true"
assert_equals "B is NOT compliant (missing snyk-container-scan)" "${b_ic}" "false"
assert_equals "whole trail NOT compliant" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_nonzero "gate.rego denies"

finish
