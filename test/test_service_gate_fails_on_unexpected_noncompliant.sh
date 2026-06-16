#!/usr/bin/env bash
# Tier 1 (per-service build flow), asymmetry / fail-CLOSED. Proves an UNEXPECTED
# attestation (one not declared in the service template) that is non-compliant
# STILL makes the service trail non-compliant, so the per-service gate (`kosli
# evaluate trail --policy component.rego`) DENIES. `unexpected: true` means "not
# required by the template", NOT "ignored for compliance": a known-bad ad-hoc
# attestation cannot be sneaked past the service gate (and so cannot reach the
# binding trail). [docs/02 `unexpected`]
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

echo "## arrange -- all required present+compliant, PLUS an unexpected web.surprise (--compliant=false)"
kosli_cli create flow "${flow}" --description "service unexpected attestation" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest generic --name approval --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest approval"
kosli_cli attest artifact "${work}/web.bin" --artifact-type file --name web --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact web"
kosli_cli attest generic --name web.lint --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest web.lint"
kosli_cli attest junit --name web.unit-test --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest web.unit-test"
kosli_cli attest generic --name web.surprise --compliant=false --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest unexpected web.surprise (not in template)"

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
web_ic="$(json '.compliance_status.artifacts_statuses.web.is_compliant')"
sel='.compliance_status.artifacts_statuses.web.attestations_statuses[]? | select(.attestation_name=="surprise")'
surprise_unexpected="$(json "${sel} | .unexpected")"
surprise_ic="$(json "${sel} | .is_compliant")"
echo "  OBSERVED web.surprise unexpected   = ${surprise_unexpected:-<absent>}"
echo "  OBSERVED web.surprise is_compliant = ${surprise_ic:-<absent>}"
trail_ic="$(json '.compliance_status.is_compliant')"
echo "  OBSERVED web is_compliant          = ${web_ic} (trail=${trail_ic})"

echo "## assert -- unexpected != ignored: a non-compliant unexpected attestation denies the per-service gate"
assert_equals "web.surprise flagged unexpected=true" "${surprise_unexpected}" "true"
assert_equals "web.surprise is non-compliant"        "${surprise_ic}" "false"
assert_equals "artifact web NOT compliant (unexpected evidence still counts)" "${web_ic}" "false"
assert_equals "service trail NOT compliant" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/component.rego" --assert
assert_exit_nonzero "kosli evaluate trail (the per-service gate) DENIES"

finish
