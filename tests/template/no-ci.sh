#!/usr/bin/env bash
# Checks a project without CI (ci: no): it gets no workflow and nothing that names one, and without
# CI publishing to npm and deploying to GitHub Pages, which both run on it, default to no and Copier
# refuses them.
# Usage: tests/template/no-ci.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "::error::$1" >&2; exit 1; }

# The case, the same with browser tests, whose Playwright version test reads ci.yml, and the
# defaults of a public library and of a site, which publish to npm or deploy to GitHub Pages with CI
"$root/tests/template/render.sh" vue-app-no-ci "$work/project"
copier copy --vcs-ref HEAD --defaults --data-file "$root/tests/template/cases/vue-app-no-ci.yml" \
  --data browser_tests=true --quiet "$root" "$work/browser"
for kind in library site; do
  copier copy --vcs-ref HEAD --defaults --quiet --data name=demo --data description=Demo \
    --data visibility=public --data ci=false --data kind=$kind "$root" "$work/$kind" ||
    fail "Copier refused the defaults of a public $kind without CI"
done
for project in "$work/project" "$work/browser" "$work/library" "$work/site"; do
  [[ -z $(find "$project/.github" -name '*.yml' -print -quit) ]] ||
    fail "a project without CI got a workflow: $(find "$project/.github" -name '*.yml')"
  ! grep -rqi 'ci\.yml\|CI runs\|^- `\.github/workflows/`' "$project" --exclude-dir=.git ||
    fail "a project without CI names it: $(grep -rli 'ci\.yml\|CI runs' "$project" --exclude-dir=.git)"
done
[[ -f $work/browser/playwright.config.ts ]] || fail 'the browser tests are missing without CI'
[[ ! -e $work/browser/tests/playwright-version.test.ts ]] ||
  fail 'a project without CI got tests/playwright-version.test.ts, which reads ci.yml'

# refused <message> <copier --data>...: Copier must refuse the answers with the message
refused() {
  local message=$1 out
  shift
  rm -rf "$work/refused"
  if out=$(copier copy --vcs-ref HEAD --defaults --quiet --data name=demo --data description=Demo \
    --data ci=false "$@" "$root" "$work/refused" 2>&1); then
    fail "Copier rendered ci: false with $*"
  fi
  grep -qF "$message" <<<"$out" || fail "Copier refused ci: false with $* without '$message': $out"
}
refused 'publishing to npm needs CI' --data kind=library --data publish=true
refused 'deploying to GitHub Pages needs CI' --data kind=site --data pages=true
refused 'deploying to GitHub Pages needs CI' --data kind=library --data workspace=monorepo \
  --data publish=false --data pages=true

echo 'ci: no: no workflow and nothing naming one, publishing and Pages off by default and refused'
