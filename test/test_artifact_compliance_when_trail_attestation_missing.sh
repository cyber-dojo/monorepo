#!/usr/bin/env bash
# Question this answers against the CURRENT server (not old data):
#
#   A flow template has a trail-level attestation (pull-request) AND an
#   artifact-level junit for artifact A. We attest A fully (lint + unit-test) but
#   NEVER attest the trail-level pull-request. What does the trail JSON then say
#   about  .compliance_status.artifacts_statuses.A.is_compliant  -- and is the
#   trail itself compliant?
#
# Pure kosli CLI sequence. Every asserted value is read from a live
# `kosli get trail --output json`. The template / junit / artifact are CLI
# INPUTS (arguments), not fabricated responses.
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
source "${here}/lib.sh"

flow="$(basename "$0" .sh | tr '_' '-')"   # dedicated flow named after this test
work="${_tmpdir}/work"
mkdir -p "${work}/reports"

# Controlled, disposable git repo: we author the exact commit the CLI will read.
# Every attest gets --repo-root pointing HERE, so it never reads an ambient repo
# under the cwd. The trail is keyed on this controlled commit.
repo="${work}/repo"
sha="$(make_commit "${repo}" "trail-miss test commit")"
trail="${sha}"
repo_url="https://github.com/cyber-dojo/monorepo"
# attest artifact takes --commit-url/--build-url (build-url required); attest
# generic/junit do NOT (see docs/findings.md) -- they use --commit + --repo-root.
artifact_git_flags=(--repo-root "${repo}" --commit "${sha}" \
  --commit-url "${repo_url}/commit/${sha}" --build-url "${repo_url}/actions/runs/1")
commit_git_flags=(--repo-root "${repo}" --commit "${sha}")

# --- CLI inputs -------------------------------------------------------------
# Dogfood the real monorepo template: trail-level pull-request + artifact
# A{lint, unit-test}.
"${root}/bin/scoped-template" --repo-root "${root}" '["A"]' > "${work}/template.yml"
printf 'artifact A for %s\n' "${flow}" > "${work}/A.bin"   # unique fingerprint per test
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<testsuite name="A" tests="1" failures="0" errors="0">' \
  '  <testcase classname="A" name="smoke"/>' \
  '</testsuite>' > "${work}/reports/junit.xml"

echo "## arrange"
kosli_cli create flow "${flow}" --description "trail-miss system test" --template-file "${work}/template.yml"
assert_exit_zero "create flow"

kosli_cli begin trail "${trail}" --flow "${flow}"
assert_exit_zero "begin trail"

kosli_cli attest artifact "${work}/A.bin" --artifact-type file --name A \
  --flow "${flow}" --trail "${trail}" "${artifact_git_flags[@]}"
assert_exit_zero "attest artifact A"

kosli_cli attest generic --name A.lint --compliant=true \
  --flow "${flow}" --trail "${trail}" "${commit_git_flags[@]}"
assert_exit_zero "attest A.lint"

kosli_cli attest junit --name A.unit-test --results-dir "${work}/reports" \
  --flow "${flow}" --trail "${trail}" "${commit_git_flags[@]}"
assert_exit_zero "attest A.unit-test"

# NB: the trail-level pull-request is deliberately NEVER attested.

echo "## act -- read the real trail compliance JSON (only source of asserted data)"
kosli_cli get trail "${trail}" --flow "${flow}" --output json
assert_exit_zero "get trail --output json"
artifact_ic="$(json '.compliance_status.artifacts_statuses.A.is_compliant')"
trail_ic="$(json '.compliance_status.is_compliant')"
pr_status="$(json '.compliance_status.attestations_statuses[]? | select(.attestation_name=="pull-request") | .status')"

echo "  OBSERVED .artifacts_statuses.A.is_compliant = ${artifact_ic}"
echo "  OBSERVED .is_compliant (trail)              = ${trail_ic}"
echo "  OBSERVED trail-level pull-request status    = ${pr_status:-<absent>}"

echo "## assert"
# The guarantee gate.rego depends on: a missing expected attestation => trail
# is not compliant, and the gate denies.
assert_equals "trail is NOT compliant when pull-request unattested" "${trail_ic}" "false"

kosli_cli evaluate trail "${trail}" --flow "${flow}" --policy "${root}/policy/gate.rego" --assert
assert_exit_nonzero "gate.rego denies the trail"

# Pinned characterisation (observed on a fresh server): a MISSING trail-level
# attestation drags the ARTIFACT to non-compliant too, even though A's own
# attestations (lint, unit-test) are present and compliant. If a future server
# version flips this, this assert catches it.
assert_equals "artifact A is non-compliant while trail-level pull-request MISSING" "${artifact_ic}" "false"

finish
