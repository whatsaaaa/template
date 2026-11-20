#!/usr/bin/env bash
# Checks what the answers make of .github/workflows/pages.yml, the caller of the shared Pages
# workflow: a project laid out as the template lays it out deploys `build` from the dist/ of its
# pages, as before the build script and the artifact path were answers; a single-package library
# deploys the docs site it builds itself, and gets no docs app in apps/docs; a workspace library
# with a docs site of its own names its script and path too; and Copier refuses the answers that
# deploy nothing.
# Usage: tests/template/pages.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "::error::$1" >&2; exit 1; }

# deploys <project> <the inputs of the call, one a line>: what pages.yml passes, and that
# .copier-answers.yml records it, so the next update renders the same
deploys() {
  local project=$1 want=$2 have script=build path
  have=$(sed -e '1,/^    with:$/d' -e 's/^      //' "$project/.github/workflows/pages.yml")
  [[ $have == "$want" ]] ||
    fail "pages.yml of ${project##*/} passes '${have//$'\n'/, }', not '${want//$'\n'/, }'"
  [[ $want != build-script:* ]] || script=$(sed -n 's/^build-script: //p' <<<"$want")
  path=$(sed -n 's/^artifact-path: //p' <<<"$want")
  grep -qx "pages_build_script: $script" "$project/.copier-answers.yml" ||
    fail ".copier-answers.yml of ${project##*/} does not record the build script $script"
  grep -qx "pages_artifact_path: $path" "$project/.copier-answers.yml" ||
    fail ".copier-answers.yml of ${project##*/} does not record the artifact path $path"
}

# The template's own layouts, from the answers of their cases, which name neither
while read -r case path; do
  "$root/tests/template/render.sh" "$case" "$work/$case"
  deploys "$work/$case" "artifact-path: $path"
done <<'EOF'
astro-site dist
plain-site dist
react-app-monorepo packages/demo-react-app/dist
library-monorepo apps/docs/dist
library-retrofit-docs apps/docs/dist
EOF

# A single-package library: the site it builds itself, and nothing of a docs app, which is a
# member of a workspace. An existing one, and a new one with the starter files.
"$root/tests/template/render.sh" library-single-docs "$work/library-single-docs"
copier copy --vcs-ref HEAD --defaults --quiet --data-file "$root/tests/template/cases/library-single-docs.yml" \
  --data starter=true "$root" "$work/new"
for project in "$work/library-single-docs" "$work/new"; do
  deploys "$project" $'build-script: docs:build\nartifact-path: docs/.vitepress/dist'
  [[ ! -e $project/apps ]] || fail "a single-package library got apps/: $(find "$project/apps" -type f)"
  ! grep -q '^packages:\|apps/' "$project/pnpm-workspace.yaml" ||
    fail "pnpm-workspace.yaml of a single-package library names workspace members"
  [[ -z $(find "$project" \( -name 'vite.config.ts' -o -name index.html \) -print -quit) ]] ||
    fail 'a single-package library got the page of a docs app'
  # Without the docs app, the template has no page to test in a browser
  [[ ! -e $project/playwright.config.ts ]] ||
    fail 'a single-package library got browser tests although it did not ask for them'
done
[[ -f $work/new/src/index.ts ]] || fail 'a new single-package library with a docs site got no starter src/'

# A workspace library with a docs site of its own in apps/docs, as form-builder has VitePress
copier copy --vcs-ref HEAD --defaults --quiet --data-file "$root/tests/template/cases/library-monorepo.yml" \
  --data pages_build_script=docs:build --data pages_artifact_path=apps/docs/.vitepress/dist \
  "$root" "$work/own"
deploys "$work/own" $'build-script: docs:build\nartifact-path: apps/docs/.vitepress/dist'

# refused <message> <copier --data>...: Copier must refuse the answers with the message
refused() {
  local message=$1 out
  shift
  rm -rf "$work/refused"
  if out=$(copier copy --vcs-ref HEAD --defaults --quiet --data name=demo --data description=Demo \
    "$@" "$root" "$work/refused" 2>&1); then
    fail "Copier rendered $*"
  fi
  grep -qF "$message" <<<"$out" || fail "Copier refused $* without '$message': $out"
}
# A single-package library's docs site is its own, so no default names its script or its path
single=(--data kind=library --data workspace=single --data pages=true)
refused 'Question "pages_build_script" is required' "${single[@]}" \
  --data pages_artifact_path=docs/.vitepress/dist
refused 'Question "pages_artifact_path" is required' "${single[@]}" \
  --data pages_build_script=docs:build
# The template renders it no page, so a new one has none to test in a browser
refused 'a new library has no page to test' "${single[@]}" --data pages_build_script=docs:build \
  --data pages_artifact_path=docs/.vitepress/dist --data browser_tests=true
# The caller passes both as they are: a script name, and a directory inside the repository
for script in '' 'docs build' '-r' 'build:' 'build # all'; do
  refused 'the name of a package.json script' --data kind=site --data "pages_build_script=$script"
done
for path in '' /dist dist/ ./dist ../dist docs/../dist 'my site'; do
  refused 'a directory from the root of the repository' --data kind=site \
    --data "pages_artifact_path=$path"
done

echo 'pages: the template'"'"'s layouts deploy build from dist/ as before, a single-package library its own docs site without a docs app, a script or path that deploys nothing refused'
