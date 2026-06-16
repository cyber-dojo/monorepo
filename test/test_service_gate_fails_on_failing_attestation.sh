#!/usr/bin/env bash
# Tier 1 (per-service build flow), asymmetry. Proves a present-but-FAILING
# attestation (not just a missing one) makes the service trail non-compliant, so
# the per-service gate (`kosli evaluate trail --policy component.rego`) DENIES
# (non-zero). Everything is attested, but web.lint is reported --compliant=false.
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
printf 'artifact web for %s\n' "${flow}" > "${work}/web.bin"   # unique fingerprint per test

cat > "${work}/template.yml" <<'YML'
version: 1
trail:
  attestations:
    - { name: approval, type: generic }
  artifacts:
    - name: web
      attestations:
        - { name: lint, type: generic }
        - { name: unit-test, type: junit }
YML

echo "## arrange -- attest everything, but web.lint is --compliant=false"
kosli_cli create flow "${flow}" --description "service failing attestation" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest generic --name approval --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest approval"
kosli_cli attest artifact "${work}/web.bin" --artifact-type file --name web --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact web"
kosli_cli attest generic --name web.lint --compliant=false --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest web.lint (non-compliant)"
kosli_cli attest junit --name web.unit-test --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest web.unit-test"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
web_ic="$(json '.compliance_status.artifacts_statuses.web.is_compliant')"
trail_ic="$(json '.compliance_status.is_compliant')"
lint_ic="$(json '.compliance_status.artifacts_statuses.web.attestations_statuses[]? | select(.attestation_name=="lint") | .is_compliant')"
echo "  OBSERVED web.lint is_compliant = ${lint_ic}"
echo "  OBSERVED web is_compliant      = ${web_ic} (trail=${trail_ic})"

echo "## assert -- a failing attestation => service trail non-compliant + per-service gate denies"
assert_equals "web.lint reported non-compliant" "${lint_ic}" "false"
assert_equals "artifact web NOT compliant" "${web_ic}" "false"
assert_equals "service trail NOT compliant" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/component.rego" --assert
assert_exit_nonzero "kosli evaluate trail (the per-service gate) DENIES"

finish
