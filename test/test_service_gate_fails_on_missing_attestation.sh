#!/usr/bin/env bash
# Tier 1 (per-service build flow), asymmetry. Proves a single MISSING artifact-
# level attestation makes the service trail non-compliant, so the per-service gate
# (`kosli evaluate trail --policy component.rego`) DENIES (non-zero). A service that
# cannot pass its own gate is never bound into the binding trail by the
# orchestrator. Here A's artifact and A.lint are attested but A.unit-test is
# omitted. [docs/01 "missing -> non-compliant", docs/06 fail-closed]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "service missing-attestation commit")"
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
kosli_cli create flow "${flow}" --description "service missing attestation" --template-file "${work}/template.yml"
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
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
trail_ic="$(json '.compliance_status.is_compliant')"
ut_status="$(json '.compliance_status.artifacts_statuses.A.attestations_statuses[]? | select(.attestation_name=="unit-test") | .status')"
echo "  OBSERVED A.unit-test status         = ${ut_status:-<absent>}"
echo "  OBSERVED A is_compliant             = ${a_ic} (trail=${trail_ic})"

echo "## assert -- one missing attestation => service trail non-compliant + per-service gate denies"
assert_equals "A.unit-test reported as MISSING" "${ut_status}" "MISSING"
assert_equals "artifact A NOT compliant" "${a_ic}" "false"
assert_equals "service trail NOT compliant" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/component.rego" --assert
assert_exit_nonzero "kosli evaluate trail (the per-service gate) DENIES"

finish
