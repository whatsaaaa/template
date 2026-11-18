#!/usr/bin/env bash
# Run apply.sh against recorded API responses (no network) and compare its
# output and its write requests with test/expected/. UPDATE=1 rewrites them.
#
# Usage: settings/test/run.sh

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
apply=$here/../apply.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0

# run_case <case> <fixture> <apply.sh arguments>...: the output, the exit
# status and every request that is not a GET, compared with expected/<case>.
run_case() {
  local case=$1 fixture=$here/fixtures/$2.json code=0
  shift 2
  : >"$work/calls"
  PATH="$here/bin:$PATH" FAKE_GH_RESPONSES=$fixture FAKE_GH_CALLS=$work/calls \
    "$apply" "$@" >"$work/out" 2>&1 || code=$?
  {
    cat "$work/out"
    echo "exit $code"
    grep -v '^GET ' "$work/calls" || true
  } >"$work/actual"
  if [[ -n ${UPDATE-} ]]; then
    cp "$work/actual" "$here/expected/$case"
  elif ! diff -u "$here/expected/$case" "$work/actual"; then
    echo "FAIL $case"
    failed=1
    return
  fi
  echo "ok   $case"
}

# Recorded from GitHub: a repository with a ruleset, environments and Pages
# whose required checks come from its override, one with a settings override, a private one, and a new one with neither a
# ruleset nor the environment it needs.
run_case form-builder-check form-builder whatsaaaa/form-builder --check
run_case form-builder-apply form-builder whatsaaaa/form-builder
run_case dotfiles-check dotfiles whatsaaaa/dotfiles --check
run_case dotfiles-apply dotfiles whatsaaaa/dotfiles
run_case ui-vue-check ui-vue whatsaaaa/ui-vue --check
run_case ui-vue-apply ui-vue whatsaaaa/ui-vue
run_case config-check config whatsaaaa/config --check
run_case config-apply config whatsaaaa/config

# Written by hand: a repository in line with its .copier-answers.yml, which
# must report nothing and change nothing, and the same with answers overridden.
run_case demo-check demo whatsaaaa/demo --check
run_case demo-apply demo whatsaaaa/demo
run_case demo-set demo whatsaaaa/demo --check --set publish=false --set 'description="Other"'
run_case demo-answers-file demo whatsaaaa/demo --check --answers "$here/fixtures/answers.yml"

# Answers wrapped over several lines must read whole: quoted ones match, and a
# plain one shows whole in its drift.
run_case demo-answers-folded demo whatsaaaa/demo --check --answers "$here/fixtures/answers-folded.yml"
run_case demo-answers-folded-double demo whatsaaaa/demo --check --answers "$here/fixtures/answers-folded-double.yml"
run_case demo-answers-folded-plain demo whatsaaaa/demo --check --answers "$here/fixtures/answers-folded-plain.yml"

# The same repository drifted in the areas the recordings leave in line:
# security toggles, Pages, an environment, branch policies and labels.
run_case demo-drifted-check demo-drifted whatsaaaa/demo --check
run_case demo-drifted-apply demo-drifted whatsaaaa/demo

# Usage errors.
run_case usage demo whatsaaaa/demo --nope

exit "$failed"
