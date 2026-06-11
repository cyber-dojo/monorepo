#!/usr/bin/env bash
# Component B build/test driver (Ruby).
#
# Different stages from A on purpose: rubocop (lint-as-junit) and a container
# scan. Outputs are deterministic placeholders so the example runs without a
# real toolchain.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
reports="reports"
dist="dist"

usage() {
  cat <<'EOF'
Usage: source/B/build.sh <stage>

Stages:
  build       Syntax-check the sources.
  rubocop     Run rubocop, emit reports/rubocop-junit.xml.
  snyk-scan   Run the container scan, emit reports/snyk.json.
  image       Package the artifact into dist/B.tar.

Options:
  -h          Show this help and exit.

Example:
  source/B/build.sh rubocop
EOF
}

case "${1:-}" in
  -h|--help|"")
    usage
    ;;
  build)
    ruby -c app.rb
    echo "B: build ok"
    ;;
  rubocop)
    mkdir -p "$reports"
    cat > "$reports/rubocop-junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="B.rubocop" tests="1" failures="0" errors="0">
  <testcase classname="B.rubocop" name="style"/>
</testsuite>
XML
    echo "B: rubocop ok"
    ;;
  snyk-scan)
    mkdir -p "$reports"
    echo '{"tool":"snyk","vulnerabilities":0}' > "$reports/snyk.json"
    echo "B: snyk-scan ok"
    ;;
  image)
    mkdir -p "$dist"
    tar -cf "$dist/B.tar" app.rb
    echo "B: image -> $dist/B.tar"
    ;;
  *)
    echo "unknown stage: $1" >&2
    usage
    exit 2
    ;;
esac
