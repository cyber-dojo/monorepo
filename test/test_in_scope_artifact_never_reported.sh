#!/usr/bin/env bash
# Proves (asymmetry): an artifact the (scoped) template expects but which is never
# reported makes the trail non-compliant and the gate deny -- "silence is never
# success". Only the trail-level approval is attested; artifact A is never sent.
# Also characterises docs/06 open-question 1: does artifacts_statuses omit an
# expected-but-unreported artifact, or list it as MISSING? (Observed + printed.)
# [docs/01 "silence is never success", docs/06]
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"; mkdir -p "${work}"
repo="${work}/repo"
sha="$(make_commit "${repo}" "artifact-never-reported commit")"
trail="${sha}"
cgf=(--repo-root "${repo}" --commit "${sha}")

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

echo "## arrange -- attest only the trail-level approval; never report artifact A"
kosli_cli create flow "${flow}" --description "artifact never reported" --template-file "${work}/template.yml"
assert_exit_zero "create flow"
kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"
kosli_cli attest generic --name approval --compliant=true --flow "${flow}" --trail "${trail}" "${cgf[@]}"
assert_exit_zero "attest approval"
# artifact A and its attestations deliberately NEVER reported.

echo "## act"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
trail_ic="$(json '.compliance_status.is_compliant')"
a_present="$(json '.compliance_status.artifacts_statuses | has("A")')"
a_status="$(json '.compliance_status.artifacts_statuses.A.status // "<absent>"')"
echo "  OBSERVED trail is_compliant     = ${trail_ic}"
echo "  OBSERVED artifacts_statuses.A present = ${a_present} (status=${a_status})"

echo "## assert -- an unreported in-scope artifact => non-compliant + gate denies"
assert_equals "trail NOT compliant when artifact A never reported" "${trail_ic}" "false"
kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_nonzero "gate.rego denies"

finish
