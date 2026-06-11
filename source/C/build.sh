#!/usr/bin/env bash
# Component C build/test driver (Go).
#
# The simplest of the three: build, unit-test, package. Outputs are deterministic
# placeholders so the example runs without a real toolchain.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
reports="reports"
dist="dist"

usage() {
  cat <<'EOF'
Usage: source/C/build.sh <stage>

Stages:
  build       Compile-check the sources.
  unit-test   Run unit tests, emit reports/junit.xml.
  image       Package the artifact into dist/C.tar.

Options:
  -h          Show this help and exit.

Example:
  source/C/build.sh unit-test
EOF
}

case "${1:-}" in
  -h|--help|"")
    usage
    ;;
  build)
    # gofmt is always present in a Go toolchain; fall back to a no-op if absent.
    command -v gofmt >/dev/null 2>&1 && gofmt -l main.go >/dev/null || true
    echo "C: build ok"
    ;;
  unit-test)
    mkdir -p "$reports"
    cat > "$reports/junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="C" tests="1" failures="0" errors="0">
  <testcase classname="C.smoke" name="greet"/>
</testsuite>
XML
    echo "C: unit-test ok"
    ;;
  image)
    mkdir -p "$dist"
    tar -cf "$dist/C.tar" main.go
    echo "C: image -> $dist/C.tar"
    ;;
  *)
    echo "unknown stage: $1" >&2
    usage
    exit 2
    ;;
esac
