#!/usr/bin/env bash
# Tier 1 (per-service build flow). Characterises, against the CURRENT server, what
# a MISSING trail-level attestation does to the per-service gate. web's artifact and
# both its attestations (lint, unit-test) are present and compliant, but the
# trail-level 'approval' is NEVER attested. A missing trail-level attestation makes
# the trail non-compliant (and on the current server also drags the ARTIFACT to
# non-compliant), so the per-service gate (`kosli evaluate trail --policy
# component.rego`) DENIES. If a future server flips the artifact-dragging, the
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

echo "## arrange -- attest web fully, but NEVER the trail-level approval"
kosli_cli create flow "${flow}" --description "service trail attestation missing" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest artifact "${work}/web.bin" --artifact-type file --name web --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact web"
kosli_cli attest generic --name web.lint --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest web.lint"
kosli_cli attest junit --name web.unit-test --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest web.unit-test"
# Trail-level approval deliberately NEVER attested.

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
web_ic="$(json '.compliance_status.artifacts_statuses.web.is_compliant')"
trail_ic="$(json '.compliance_status.is_compliant')"
approval_status="$(json '.compliance_status.attestations_statuses[]? | select(.attestation_name=="approval") | .status')"
echo "  OBSERVED trail-level approval status = ${approval_status:-<absent>}"
echo "  OBSERVED web is_compliant              = ${web_ic} (trail=${trail_ic})"

echo "## assert -- missing trail-level attestation => trail non-compliant + per-service gate denies"
assert_equals "trail-level approval reported MISSING" "${approval_status}" "MISSING"
assert_equals "service trail NOT compliant" "${trail_ic}" "false"
# Pinned characterisation: a MISSING trail-level attestation drags the ARTIFACT to
# non-compliant even though web's own attestations all pass.
assert_equals "artifact web dragged non-compliant by missing trail-level attestation" "${web_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/component.rego" --assert
assert_exit_nonzero "kosli evaluate trail (the per-service gate) DENIES"

finish
