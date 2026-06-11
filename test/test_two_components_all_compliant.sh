#!/usr/bin/env bash
# Proves the central "tie compliance together" claim, positive direction: with a
# scoped template of two components {A,B} that share no attestation, when BOTH are
# fully compliant the whole commit is compliant and the gate allows. The positive
# control for the AND demonstrated by test_two_components_one_not_compliant.sh.
# [docs/01 tie-together goal, docs/05 allow-when-compliant]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "two-components-all-good commit")"
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

echo "## arrange -- both A and B fully attested and compliant"
kosli_cli create flow "${flow}" --description "two components, all good" --template-file "${work}/template.yml"
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
kosli_cli attest artifact "${work}/B.bin" --artifact-type file --name B --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact B"
kosli_cli attest junit --name B.rubocop --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest B.rubocop"
kosli_cli attest generic --name B.snyk-container-scan --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest B.snyk-container-scan"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
b_ic="$(json '.compliance_status.artifacts_statuses.B.is_compliant')"
echo "  OBSERVED trail is_compliant = ${trail_ic} (A=${a_ic}, B=${b_ic})"

echo "## assert -- both components compliant => whole commit compliant + gate allows"
assert_equals "A compliant" "${a_ic}" "true"
assert_equals "B compliant" "${b_ic}" "true"
assert_equals "whole trail compliant" "${trail_ic}" "true"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_zero "gate.rego ALLOWS the compliant trail"

finish
