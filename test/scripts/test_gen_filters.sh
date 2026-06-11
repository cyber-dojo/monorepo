#!/usr/bin/env bash
# Proves bin/gen-filters derives the dorny/paths-filter rules from the fragment
# files alone: each source/<X>/kosli.yml yields "X: ['source/X/**']". This is the
# "one fact, two uses" discovery in docs/04 (fragment presence drives both which
# components exist and how their changes are detected).
set -Eeu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
source "${here}/../assert.sh"

out="$("${root}/bin/gen-filters" --repo-root "${root}")"
printf '%s\n' "${out}" | sed 's/^/  filters: /'

assert_contains "A maps to source/A/**" "${out}" "A: ['source/A/**']"
assert_contains "B maps to source/B/**" "${out}" "B: ['source/B/**']"
assert_contains "C maps to source/C/**" "${out}" "C: ['source/C/**']"

finish
