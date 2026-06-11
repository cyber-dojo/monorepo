# Bring up / reset a local Kosli server so each test starts from a COMPLETELY
# EMPTY server -- the same idea as the server's `make demo`, minus the bulk data.
#
# Isolation model: the suite resets the server to empty ONCE (run.sh calls
# reset_to_empty before the loop). Per-test isolation then comes from each test
# using its own flow (named after the test) and a UNIQUE artifact fingerprint --
# a fingerprint's compliance spans flows/trails, so shared fingerprints (not
# shared flows) are the contamination risk.
#
# It reuses the server repo's own targets and in-container init scripts (running
# them, never editing that repo). The only values copied out of kosli-dev/server:
#   org   : test-organization                  (demo/init/create_test_org.py)
#   token : ci-reporter service-account key     (src/auth/kosli_devs.py)
#           which create_populated_org adds to test-organization
#
# Override SERVER_REPO if your checkout lives elsewhere.
set -Eeu

_test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_REPO="${SERVER_REPO:-$(cd "${_test_dir}/../../../kosli-dev/server" 2>/dev/null && pwd || true)}"

# Resolve CONTAINER, PORT and KOSLI_HOST from the server repo's own env.
_resolve_env() {
  pushd "${SERVER_REPO}" >/dev/null
  source bin/container_env.sh demo
  popd >/dev/null
  if [ "${PORT}" = "80" ]; then export KOSLI_HOST="http://localhost"; else export KOSLI_HOST="http://localhost:${PORT}"; fi
}

_server_running() { docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; }

# Bring the server up. Cold (default): rebuild image + fresh empty containers.
# Fast (KOSLI_TEST_FAST=true): reuse already-running containers to skip the
# rebuild. Isolation is unaffected either way -- reset_to_empty() still wipes the
# DB before every test.
bootstrap_up() {
  [ -d "${SERVER_REPO}" ] || { echo "server repo not found: set SERVER_REPO" >&2; return 1; }
  _resolve_env
  if [ "${KOSLI_TEST_FAST:-false}" = "true" ] && _server_running; then
    echo "bootstrap: reusing running demo server (fast mode); DB reset once before the suite"
  else
    make -C "${SERVER_REPO}" demo_empty
  fi
}

# Reset the server to empty (drop all data) and recreate the minimal scaffolding
# (org owner users + test-organization). Called ONCE before the suite.
reset_to_empty() {
  docker exec "${CONTAINER}" sh -c "/demo/init/clear_db.py"
  docker exec "${CONTAINER}" /demo/init/create_dev_users.py descope "${CI:-}"
  docker exec "${CONTAINER}" /demo/init/create_test_org.py descope
  export KOSLI_ORG="test-organization"
  export KOSLI_API_TOKEN="cir_L2XffuXjW6j3CvF8d2o10JZB4jiavL2SoTRUxKn"
}

bootstrap_down() { make -C "${SERVER_REPO}" down_demo; }
