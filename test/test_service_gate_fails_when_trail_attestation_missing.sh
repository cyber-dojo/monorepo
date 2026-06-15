#!/usr/bin/env bash
# Tier 1 (per-service build flow). Characterises, against the CURRENT server, what
# a MISSING trail-level attestation does to the service's own gate. A's artifact
# and both its attestations (lint, unit-test) are present and compliant, but the
# trail-level 'approval' is NEVER attested. On the current server a missing
# trail-level attestation drags the ARTIFACT to non-compliant, so the service's
# self-check (`kosli assert artifact`) DENIES. If a future server flips this, the
# pinned assert below catches it. [docs/findings, docs/06]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}/reports"
repo="${work}/repo"
sha="$(make_commit "${repo}" "service trail-miss commit")"
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

echo "## arrange -- attest A fully, but NEVER the trail-level approval"
kosli_cli create flow "${flow}" --description "service trail attestation missing" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact A"
kosli_cli attest generic --name A.lint --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.lint"
kosli_cli attest junit --name A.unit-test --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.unit-test"
# Trail-level approval deliberately NEVER attested.

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
approval_status="$(json '.compliance_status.attestations_statuses[]? | select(.attestation_name=="approval") | .status')"
echo "  OBSERVED trail-level approval status = ${approval_status:-<absent>}"
echo "  OBSERVED A is_compliant              = ${a_ic}"

echo "## assert -- missing trail-level attestation => artifact dragged non-compliant + self-check denies"
assert_equals "trail-level approval reported MISSING" "${approval_status}" "MISSING"
# Pinned characterisation: a MISSING trail-level attestation drags the ARTIFACT to
# non-compliant even though A's own attestations all pass.
assert_equals "artifact A dragged non-compliant by missing trail-level attestation" "${a_ic}" "false"
kosli_cli assert artifact "${work}/A.bin" --artifact-type file --flow "${flow}"
assert_exit_nonzero "kosli assert artifact (the service self-check) DENIES"

finish
