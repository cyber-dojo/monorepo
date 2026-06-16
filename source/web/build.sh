#!/usr/bin/env bash
# Component web build/test driver (Python).
#
# Produces the artifact and report files that web's workflow attests. Outputs are
# deterministic placeholders so the example runs without a real toolchain; in a
# real component these stages would invoke flake8, pytest, a packager, etc.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
reports="reports"
dist="dist"

usage() {
  cat <<'EOF'
Usage: source/web/build.sh <stage>

Stages:
  build       Byte-compile the sources.
  unit-test   Run unit tests, emit reports/junit.xml.
  lint        Run the linter, emit reports/lint.json.
  image       Package the artifact into dist/web.tar.

Options:
  -h          Show this help and exit.

Example:
  source/web/build.sh unit-test
EOF
}

case "${1:-}" in
  -h|--help|"")
    usage
    ;;
  build)
    python3 -c "import py_compile; py_compile.compile('app.py', doraise=True)"
    echo "web: build ok"
    ;;
  unit-test)
    mkdir -p "$reports"
    cat > "$reports/junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="web" tests="1" failures="0" errors="0">
  <testcase classname="web.smoke" name="imports"/>
</testsuite>
XML
    echo "web: unit-test ok"
    ;;
  lint)
    mkdir -p "$reports"
    echo '{"tool":"flake8","violations":0}' > "$reports/lint.json"
    echo "web: lint ok"
    ;;
  image)
    mkdir -p "$dist"
    tar -cf "$dist/web.tar" app.py
    echo "web: image -> $dist/web.tar"
    ;;
  *)
    echo "unknown stage: $1" >&2
    usage
    exit 2
    ;;
esac
