#!/usr/bin/env bash
# Tier 1 (per-service build flow). Proves the per-service gate -- `kosli evaluate
# trail --policy component.rego` against the service flow -- PASSES (exit 0) when
# the service flow is fully compliant. This is the positive control: only when this
# passes does the orchestrator bind the artifact into the binding trail (see the
# cross-tier test). [docs/03 "the bind job", docs/05]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "service gate passes commit")"
trail="${sha}"
url="https://github.com/cyber-dojo/monorepo"
agf=(--repo-root "${repo}" --commit "${sha}" --commit-url "${url}/commit/${sha}" --build-url "${url}/actions/runs/1")
cgf=(--repo-root "${repo}" --commit "${sha}")
write_junit "${work}/reports"
printf 'artifact A for %s\n' "${flow}" > "${work}/A.bin"   # unique fingerprint per test

# A service flow template: a trail-level attestation (generic 'approval' stands in
# for the real pull-request, which needs GitHub) plus artifact A{lint,unit-test}.
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

echo "## arrange -- everything the service flow requires, all compliant"
kosli_cli create flow "${flow}" --description "service gate passes" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest generic --name approval --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest trail-level approval"
kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A --flow "${flow}" --trail "${trail}" "${agf[@]}"
assert_exit_zero "attest artifact A"
kosli_cli attest generic --name A.lint --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.lint"
kosli_cli attest junit --name A.unit-test --results-dir "${work}/reports" --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest A.unit-test"

echo "## act -- read the service flow's view of A, then run the per-service gate"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
a_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
trail_ic="$(json '.compliance_status.is_compliant')"
echo "  OBSERVED A is_compliant in service flow = ${a_ic} (trail=${trail_ic})"

echo "## assert -- service flow compliant => the per-service gate exits 0"
assert_equals "artifact A compliant in service flow" "${a_ic}" "true"
assert_equals "service trail compliant" "${trail_ic}" "true"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/component.rego" --assert
assert_exit_zero "kosli evaluate trail (the per-service gate) PASSES"

finish
