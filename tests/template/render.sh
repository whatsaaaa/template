#!/usr/bin/env bash
# Renders the template, as this checkout has it, with the answers of one case.
# Usage: tests/template/render.sh <case> <destination>
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
case_file="$root/tests/template/cases/$1.yml"
[[ -f $case_file ]] || { echo "no case '$1' in tests/template/cases" >&2; exit 2; }

# --vcs-ref HEAD renders this checkout, uncommitted changes included, not the latest tag
copier copy --vcs-ref HEAD --defaults --data-file "$case_file" --quiet "$root" "$2"
