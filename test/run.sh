#!/usr/bin/env bash
# Self-contained system-test entrypoint. Brings up a local Kosli server and runs
# every test_*.sh, RESETTING THE SERVER TO EMPTY BEFORE EACH TEST so no test ever
# runs against leftover state.
#
# Usage:
#   test/run.sh           cold: rebuild fresh containers, run tests, tear down.
#   test/run.sh --fast     reuse already-running containers to skip the rebuild.
#                          Still empties the DB before every test, so it is safe;
#                          it just does not rebuild the image or recreate containers.
#                          Leaves the server up afterwards for the next --fast run.
#
# Requires: docker, the kosli CLI, jq, and a kosli-dev/server checkout
# (override its location with SERVER_REPO).
#
# There is deliberately no "reuse the data" mode: starting empty is an invariant.
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
source "${here}/bootstrap.sh"

fast="false"
[ "${1:-}" = "--fast" ] && fast="true"
export KOSLI_TEST_FAST="${fast}"

bootstrap_up
# Cold mode tears down at the end. Fast mode leaves containers up for the next
# run -- safe, because the DB is emptied before every test regardless.
[ "${fast}" = "true" ] || trap 'bootstrap_down' EXIT

rc=0
for t in "${here}"/test_*.sh; do
  echo "=== ${t##*/} ==="
  reset_to_empty            # <-- every test starts from a COMPLETELY EMPTY server
  bash "${t}" || rc=1
  echo
done
exit "${rc}"
