#!/usr/bin/env bash
# Tier 1 (per-service build flow), asymmetry. Proves a present-but-FAILING
# attestation (not just a missing one) makes the service trail non-compliant, so
# the per-service gate (`kosli evaluate trail --policy component.rego`) DENIES
# (non-zero). Everything is attested, but A.lint is reported --compliant=false.
# [docs/01 asymmetry, docs/05 positive proof of compliance]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "service failing-attestation commit")"
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

echo "## arrange -- attest everything, but A.lint is --compliant=false"
kosli_cli create flow "${flow}" --description "service failing attestation" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest generic --name approval --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest approval"
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact A"
kosli_cli attest generic --name A.lint --compliant=false --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.lint (non-compliant)"
kosli_cli attest junit --name A.unit-test --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.unit-test"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
trail_ic="$(json '.compliance_status.is_compliant')"
lint_ic="$(json '.compliance_status.artifacts_statuses.A.attestations_statuses[]? | select(.attestation_name=="lint") | .is_compliant')"
echo "  OBSERVED A.lint is_compliant = ${lint_ic}"
echo "  OBSERVED A is_compliant      = ${a_ic} (trail=${trail_ic})"

echo "## assert -- a failing attestation => service trail non-compliant + per-service gate denies"
assert_equals "A.lint reported non-compliant" "${lint_ic}" "false"
assert_equals "artifact A NOT compliant" "${a_ic}" "false"
assert_equals "service trail NOT compliant" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/component.rego" --assert
assert_exit_nonzero "kosli evaluate trail (the per-service gate) DENIES"

finish
