#!/usr/bin/env bash
# Runner for the server-free script tests: these exercise bin/scoped-template and
# bin/gen-filters directly. No Kosli server, no docker -- just python3 + pyyaml.
#
# Usage: test/scripts/run.sh
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "${here}"/test_*.sh; do
  echo "=== ${t##*/} ==="
  bash "${t}" || rc=1
  echo
done
exit "${rc}"
