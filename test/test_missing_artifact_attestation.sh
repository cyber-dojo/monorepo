#!/usr/bin/env bash
# Proves (asymmetry): a single missing artifact-level attestation makes the trail
# non-compliant and the gate deny -- a missing piece is never silently treated as
# compliant. Here A's artifact and A.lint are attested but A.unit-test is omitted.
# [docs/01 "missing -> non-compliant", docs/06 fail-closed]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "missing-artifact-attestation commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
cgf=(--repo-root "${repo}" --commit "${sha}")
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

echo "## arrange -- attest everything EXCEPT A.unit-test"
kosli_cli create flow "${flow}" --description "missing artifact attestation" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest generic --name approval --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest approval"
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact A"
kosli_cli attest generic --name A.lint --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.lint"
# A.unit-test deliberately NOT attested.

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
ut_status="$(json '.compliance_status.artifacts_statuses.A.attestations_statuses[]? | select(.attestation_name=="unit-test") | .status')"
echo "  OBSERVED trail is_compliant            = ${trail_ic}"
echo "  OBSERVED A.unit-test status            = ${ut_status:-<absent>}"

echo "## assert -- one missing attestation => non-compliant + gate denies"
assert_equals "A.unit-test reported as MISSING" "${ut_status}" "MISSING"
assert_equals "trail NOT compliant with A.unit-test missing" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_nonzero "gate.rego denies"

finish
