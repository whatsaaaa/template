#!/usr/bin/env bash
# Renders the template, as this checkout has it, with the answers of one case. A case with a
# folder of its name renders into a copy of it: the existing repository moving onto the template.
# Usage: tests/template/render.sh <case> <destination>
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
case_file="$root/tests/template/cases/$1.yml"
[[ -f $case_file ]] || { echo "no case '$1' in tests/template/cases" >&2; exit 2; }
existing="$root/tests/template/cases/$1"
if [[ -d $existing ]]; then
  mkdir -p "$2"
  cp -R "$existing/." "$2"
fi

# --vcs-ref HEAD renders this checkout, uncommitted changes included, not the latest tag
copier copy --vcs-ref HEAD --defaults --data-file "$case_file" --quiet "$root" "$2"
