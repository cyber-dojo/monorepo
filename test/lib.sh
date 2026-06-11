# System-test helpers, in the style of kosli-dev/server's test/system: a
# kosli_cli wrapper that runs the REAL CLI and captures its streams, plus small
# assertions. CLI only -- every asserted value must come from a real CLI
# response (e.g. `kosli get trail --output json`), never from fabricated JSON.

: "${KOSLI_HOST:?bootstrap must export KOSLI_HOST}"
: "${KOSLI_ORG:?bootstrap must export KOSLI_ORG}"
: "${KOSLI_API_TOKEN:?bootstrap must export KOSLI_API_TOKEN}"

# Disable the CLI's CI flag-defaulting (WhichCI/ciTemplates), so a real ambient
# environment -- e.g. a genuine GITHUB_SHA when these tests later run inside
# Actions -- can never leak into a test. Every commit/repo value is then supplied
# explicitly via flags against a controlled repo: complete, hermetic control.
export KOSLI_TESTS=true

_tmpdir="$(mktemp -d)"
_out="${_tmpdir}/out"
_err="${_tmpdir}/err"
_status=0
_checks=0
_fails=0
trap 'rm -rf "${_tmpdir}"' EXIT

# Single definition of how the CLI is invoked, so its streams can be captured
# for the assertions below. Always exits 0 itself; the real status is in $_status.
kosli_cli() {
  # `|| _status=$?` keeps a non-zero CLI exit from tripping the caller's `set -e`
  # so the assertions below can inspect it instead of the script aborting.
  _status=0
  kosli --max-api-retries=0 --host "${KOSLI_HOST}" --org "${KOSLI_ORG}" "$@" >"${_out}" 2>"${_err}" || _status=$?
  return 0
}

# Evaluate a jq expression against the LAST captured stdout (real CLI JSON only).
json() { jq -r "$1" "${_out}"; }

_pass() { echo "  ok   - $1"; }
_fail() {
  _fails=$((_fails + 1))
  echo "  FAIL - $1"
  [ -s "${_err}" ] && sed 's/^/         stderr: /' "${_err}" | head -5
}

assert_exit_zero()    { _checks=$((_checks + 1)); [ "${_status}" -eq 0 ] && _pass "$1" || _fail "$1 (expected exit 0, got ${_status})"; }
assert_exit_nonzero() { _checks=$((_checks + 1)); [ "${_status}" -ne 0 ] && _pass "$1" || _fail "$1 (expected non-zero exit, got 0)"; }
assert_equals()       { _checks=$((_checks + 1)); [ "$2" = "$3" ] && _pass "$1 ($2)" || _fail "$1 (expected '$3', got '$2')"; }

# Create (if needed) a controlled, disposable git repo at $1 and add one commit
# with message $2; echo the new commit SHA. This is how a test fully controls the
# commit the kosli CLI reads (author/branch/message/sha) -- the attests point at
# it with --repo-root, never at an ambient repo under the cwd. Call it repeatedly
# to build multi-commit scenarios.
make_commit() {
  local repo="$1" message="$2"
  if [ ! -d "${repo}/.git" ]; then
    git init -q -b main "${repo}"
    git -C "${repo}" config user.name  "Kosli Test"
    git -C "${repo}" config user.email "test@kosli.local"
    git -C "${repo}" config commit.gpgsign false
  fi
  printf '%s\n' "${message}" >> "${repo}/CHANGELOG"
  git -C "${repo}" add -A
  git -C "${repo}" commit -q -m "${message}"
  git -C "${repo}" rev-parse HEAD
}

# Print summary and set the exit status (0 only if every check passed).
finish() {
  echo
  echo "${_checks} checks, ${_fails} failed"
  [ "${_fails}" -eq 0 ]
}
