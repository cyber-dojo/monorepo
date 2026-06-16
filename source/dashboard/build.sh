#!/usr/bin/env bash
# Component dashboard build/test driver (Ruby).
#
# Different stages from web on purpose: rubocop (lint-as-junit) and a container
# scan. Outputs are deterministic placeholders so the example runs without a
# real toolchain.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
reports="reports"
dist="dist"

usage() {
  cat <<'EOF'
Usage: source/dashboard/build.sh <stage>

Stages:
  build       Syntax-check the sources.
  rubocop     Run rubocop, emit reports/rubocop-junit.xml.
  snyk-scan   Run the container scan, emit reports/snyk.json.
  image       Package the artifact into dist/dashboard.tar.

Options:
  -h          Show this help and exit.

Example:
  source/dashboard/build.sh rubocop
EOF
}

case "${1:-}" in
  -h|--help|"")
    usage
    ;;
  build)
    ruby -c app.rb
    echo "dashboard: build ok"
    ;;
  rubocop)
    mkdir -p "$reports"
    cat > "$reports/rubocop-junit.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="dashboard.rubocop" tests="1" failures="0" errors="0">
  <testcase classname="dashboard.rubocop" name="style"/>
</testsuite>
XML
    echo "dashboard: rubocop ok"
    ;;
  snyk-scan)
    mkdir -p "$reports"
    echo '{"tool":"snyk","vulnerabilities":0}' > "$reports/snyk.json"
    echo "dashboard: snyk-scan ok"
    ;;
  image)
    mkdir -p "$dist"
    tar -cf "$dist/dashboard.tar" app.rb
    echo "dashboard: image -> $dist/dashboard.tar"
    ;;
  *)
    echo "unknown stage: $1" >&2
    usage
    exit 2
    ;;
esac
