# Pure assertion helpers -- no Kosli/server dependency. Shared by the server
# system tests (via lib.sh) and the server-free script tests (scripts/).

_checks=0
_fails=0

_pass() { echo "  ok   - $1"; }
_fail() { _fails=$((_fails + 1)); echo "  FAIL - $1"; }

# assert_equals <label> <actual> <expected>
assert_equals() {
  _checks=$((_checks + 1))
  if [ "$2" = "$3" ]; then _pass "$1 ($2)"; else _fail "$1 (expected '$3', got '$2')"; fi
}

# assert_contains <label> <haystack> <needle>
assert_contains() {
  _checks=$((_checks + 1))
  case "$2" in
    *"$3"*) _pass "$1" ;;
    *) _fail "$1 (does not contain: $3)"; printf '%s\n' "$2" | sed 's/^/         /' ;;
  esac
}

# assert_not_contains <label> <haystack> <needle>
assert_not_contains() {
  _checks=$((_checks + 1))
  case "$2" in
    *"$3"*) _fail "$1 (unexpectedly contains: $3)"; printf '%s\n' "$2" | sed 's/^/         /' ;;
    *) _pass "$1" ;;
  esac
}

# Print summary and set the exit status (0 only if every check passed).
finish() {
  echo
  echo "${_checks} checks, ${_fails} failed"
  [ "${_fails}" -eq 0 ]
}
