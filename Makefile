# Test entrypoints for the monorepo. Both targets are phony: they name actions,
# not files, so make never confuses them with the on-disk test/ directory (which
# is exactly why bare `make test` did nothing before this file existed).

.PHONY: server-free-tests system-tests

# No Kosli server, no docker -- just python3 + pyyaml. Exercises bin/gen-filters
# and bin/scoped-template directly.
server-free-tests:
	test/scripts/run.sh

# The full system suite. Needs docker and a local kosli-dev/server checkout
# (override its location with SERVER_REPO); brings up a fresh Kosli server, runs
# every test/test_*.sh against it, and tears down. Pass --fast via `test/run.sh`
# directly to reuse already-running containers.
system-tests:
	test/run.sh
