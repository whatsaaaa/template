#!/usr/bin/env bash
# Checks a project without CI (ci: no): it gets no workflow and nothing that names one, but a
# .no-mistakes.yaml that says so, and without CI publishing to npm and deploying to GitHub Pages,
# which both run on it, are not asked, default to no and Copier refuses them.
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
# A person answering yes to every question Copier asks, all but publish and pages answered up front:
# Copier does not validate a yes typed in, so it must not ask them without CI. With CI the same yes
# deploys the site, so the answers do reach the questions.
interactive() { # <destination> <copier --data>...
  local destination=$1
  shift
  python3 "$root/tests/template/answer-yes.py" copier copy --vcs-ref HEAD --quiet --data name=demo \
    --data description=Demo --data visibility=public --data stack=typescript --data starter=true \
    --data design_system=true --data browser_tests=false --data brand_kit=whatsaaaa \
    --data license=none --data agents_md=true "$@" "$root" "$destination" >"$work/interactive.log" ||
    fail "Copier failed with $*: $(cat "$work/interactive.log")"
}
interactive "$work/yes-library" --data kind=library --data workspace=monorepo --data framework=none \
  --data ci=false
interactive "$work/yes-site" --data kind=site --data workspace=single --data framework=astro \
  --data ci=false
interactive "$work/yes-site-ci" --data kind=site --data workspace=single --data framework=astro \
  --data ci=true
[[ -f $work/yes-site-ci/.github/workflows/pages.yml ]] ||
  fail 'a yes to every question did not deploy a site with CI to GitHub Pages'
[[ ! -e $work/yes-site-ci/.no-mistakes.yaml ]] ||
  fail 'a project with CI got .no-mistakes.yaml, which says it has none'
for project in "$work/project" "$work/browser" "$work/library" "$work/site" "$work/yes-library" \
  "$work/yes-site"; do
  [[ -z $(find "$project/.github" -name '*.yml' -print -quit) ]] ||
    fail "a project without CI got a workflow: $(find "$project/.github" -name '*.yml')"
  [[ -f $project/.no-mistakes.yaml ]] ||
    fail "a project without CI has no .no-mistakes.yaml, which says it has none: $project"
  # shellcheck disable=SC2016 # Markdown backticks, not a command
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

echo 'ci: no: no workflow and nothing naming one, .no-mistakes.yaml, publishing and Pages not asked and refused'
