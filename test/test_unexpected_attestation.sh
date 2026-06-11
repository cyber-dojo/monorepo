#!/usr/bin/env bash
# Proves (asymmetry, fail-CLOSED): an UNEXPECTED attestation -- one not declared
# in the template -- that is non-compliant STILL makes the trail non-compliant.
# So `unexpected: true` means "not required by the template", NOT "ignored for
# compliance": a known-bad ad-hoc attestation cannot be sneaked past the gate.
# (A compliant unexpected attestation, by contrast, does not affect compliance --
# e.g. the historical provenance/sbom attestations.) [docs/02 `unexpected` field]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "unexpected-attestation commit")"
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
kosli_cli create flow "${flow}" --description "unexpected attestation" --template-file "${work}/template.yml"
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
trail_ic="$(json '.compliance_status.is_compliant')"
sel='.compliance_status.artifacts_statuses.A.attestations_statuses[]? | select(.attestation_name=="surprise")'
surprise_unexpected="$(json "${sel} | .unexpected")"
surprise_ic="$(json "${sel} | .is_compliant")"
echo "  OBSERVED trail is_compliant      = ${trail_ic}"
echo "  OBSERVED A.surprise unexpected   = ${surprise_unexpected:-<absent>}"
echo "  OBSERVED A.surprise is_compliant = ${surprise_ic:-<absent>}"

echo "## assert -- unexpected != ignored: a non-compliant unexpected attestation fails the trail"
assert_equals "A.surprise flagged unexpected=true" "${surprise_unexpected}" "true"
assert_equals "A.surprise is non-compliant"        "${surprise_ic}" "false"
assert_equals "trail is NON-compliant (unexpected evidence still counts)" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_nonzero "gate.rego denies"

finish
