#!/usr/bin/env bash
# Checks that `copier update`, run as Renovate runs it (no --trust), carries a template change
# into a managed file while keeping the project's own edit to it, and leaves a seeded file alone;
# that tests/playwright-version.test.ts is managed, though the rest of tests/ is seeded: the
# template's change reaches it, and a project that deleted it keeps it deleted; that it never adds
# the starter files to an existing repository moved onto the template, nor a seeded file of the
# template's layout, such as packages/<name>/package.json, to one laid out its own way, nor a docs
# app to a single package with its own docs site, nor back a managed file it deleted; and that a
# project on the last release, whose answers lack the questions added since, updates to this
# checkout and keeps its CI, and what it deploys to GitHub Pages. The last release is the
# checkout's latest annotated tag, so a clone needs its tags: git fetch --tags.
# Usage: tests/template/update.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git_quiet() { git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false "$@" >/dev/null; }
fail() { echo "::error::$1" >&2; exit 1; }
# pages_inputs <project>: what its pages.yml passes to the shared Pages workflow
pages_inputs() { sed -e '1,/^    with:$/d' "$1/.github/workflows/pages.yml"; }

# The last release, and two projects from it as it renders its own cases: a Vue app, and a library
# with its docs app on GitHub Pages
release=$(git -C "$root" describe --abbrev=0 HEAD) || fail 'no release tag before HEAD: git fetch --tags'
mkdir "$work/template"
git -C "$root" archive "$release" | tar -C "$work/template" -xf -
git_quiet -C "$work/template" init
git_quiet -C "$work/template" add -A
git_quiet -C "$work/template" commit -m "$release"
git_quiet -C "$work/template" tag -a "$release" -m "$release"
copier copy --vcs-ref "$release" --defaults --quiet \
  --data-file "$work/template/tests/template/cases/vue-app.yml" "$work/template" "$work/release"
copier copy --vcs-ref "$release" --defaults --quiet \
  --data-file "$work/template/tests/template/cases/library-monorepo.yml" "$work/template" "$work/release-pages"
for project in release release-pages; do
  git_quiet -C "$work/$project" init
  git_quiet -C "$work/$project" add -A
  git_quiet -C "$work/$project" commit -m 'Start from the last release'
done
deployed=$(pages_inputs "$work/release-pages")

# The template as this checkout has it, uncommitted files included, released as v100.0.0
git_quiet -C "$work/template" rm -rq .
git -C "$root" ls-files --cached --others --exclude-standard |
  while read -r file; do [[ -e $root/$file ]] && printf '%s\n' "$file"; done |
  tar -C "$root" -cf - -T - | tar -C "$work/template" -xf -
git_quiet -C "$work/template" add -A
git_quiet -C "$work/template" commit -m v100.0.0
git_quiet -C "$work/template" tag v100.0.0

for project in release release-pages; do
  (cd "$work/$project" && copier update --skip-answered --defaults --vcs-ref v100.0.0 --quiet) ||
    fail "a project on $release does not update to this checkout"
  grep -qx '_commit: v100.0.0' "$work/$project/.copier-answers.yml" ||
    fail "the .copier-answers.yml of the project on $release does not record v100.0.0"
  [[ -f $work/$project/.github/workflows/ci.yml ]] || fail "the update removed ci.yml from the project on $release"
  [[ -z $(find "$work/$project" -name '*.rej' -print -quit) ]] || fail "the update of the project on $release left a rejected hunk"
  ! grep -rq '^<<<<<<<' "$work/$project" --exclude-dir=.git || fail "the update of the project on $release left a conflict"
done
[[ $(pages_inputs "$work/release-pages") == "$deployed" ]] ||
  fail "the update changed what the project on $release deploys to GitHub Pages: $(pages_inputs "$work/release-pages")"

# A project from it, which edits a managed file and a seeded one
copier copy --defaults --quiet --data-file "$root/tests/template/cases/library-single.yml" \
  "$work/template" "$work/project"
git_quiet -C "$work/project" init
# at the top, away from the template's change at the bottom, so the two do not conflict
{ echo '/scratch'; cat "$work/project/.gitignore"; } >"$work/.gitignore"
mv "$work/.gitignore" "$work/project/.gitignore"
echo 'A line of the project.' >>"$work/project/README.md"
git_quiet -C "$work/project" add -A
git_quiet -C "$work/project" commit -m 'Start from the template'

# A project with the Playwright version test, which deletes it
copier copy --defaults --quiet --data-file "$root/tests/template/cases/vue-app.yml" \
  "$work/template" "$work/app"
[[ -f $work/app/tests/playwright-version.test.ts ]] || fail 'the vue-app case has no Playwright version test to delete'
git_quiet -C "$work/app" init
git_quiet -C "$work/app" add -A
git_quiet -C "$work/app" commit -m 'Start from the template'
git_quiet -C "$work/app" rm -q tests/playwright-version.test.ts
git_quiet -C "$work/app" commit -m 'Delete the Playwright version test'

# An existing repository moved onto it, without the starter files (starter: no), which keeps the
# Playwright version test
retrofit=$root/tests/template/cases/library-retrofit
cp -R "$retrofit" "$work/retrofit"
copier copy --defaults --quiet --data-file "$retrofit.yml" "$work/template" "$work/retrofit"
git_quiet -C "$work/retrofit" init
git_quiet -C "$work/retrofit" add -A
git_quiet -C "$work/retrofit" commit -m 'Move onto the template'

# One laid out as form-builder is, which deletes the managed files it has no place for
docs=$root/tests/template/cases/library-retrofit-docs
cp -R "$docs" "$work/docs"
copier copy --defaults --quiet --data-file "$docs.yml" "$work/template" "$work/docs"
for file in packages/demo-docs/package.json apps/docs/index.html apps/docs/vite.config.ts vitest.config.ts; do
  [[ ! -e $work/docs/$file ]] || fail "the template rendered $file, a seeded file of its own layout, into the docs retrofit"
done
rm -r "$work/docs/packages/demo-docs"
git_quiet -C "$work/docs" init
git_quiet -C "$work/docs" add -A
git_quiet -C "$work/docs" commit -m 'Move onto the template'

# One laid out as the design system is: a single package whose own docs site is on GitHub Pages
single=$root/tests/template/cases/library-single-docs
cp -R "$single" "$work/single"
copier copy --defaults --quiet --data-file "$single.yml" "$work/template" "$work/single"
git_quiet -C "$work/single" init
git_quiet -C "$work/single" add -A
git_quiet -C "$work/single" commit -m 'Move onto the template'

# v100.0.1 changes the same two files, a seeded file the project kept as it was, and the
# Playwright version test
echo '# A template change' >>"$work/template/template/.gitignore.jinja"
echo 'A line of the template.' >>"$work/template/template/README.md.jinja"
echo '// A template change' >>"$work/template/template/{{ package_dir }}/src/index.ts.jinja"
echo '// A template change' >>"$work/template/template/tests/playwright-version.test.ts"
git_quiet -C "$work/template" commit -am v100.0.1
git_quiet -C "$work/template" tag v100.0.1

(cd "$work/project" && copier update --skip-answered --defaults --vcs-ref v100.0.1 --quiet)
(cd "$work/app" && copier update --skip-answered --defaults --vcs-ref v100.0.1 --quiet)
(cd "$work/retrofit" && copier update --skip-answered --defaults --vcs-ref v100.0.1 --quiet)
(cd "$work/docs" && copier update --skip-answered --defaults --vcs-ref v100.0.1 --quiet)
(cd "$work/single" && copier update --skip-answered --defaults --vcs-ref v100.0.1 --quiet)

project=$work/project
grep -qx '_commit: v100.0.1' "$project/.copier-answers.yml" || fail '.copier-answers.yml does not record v100.0.1'
grep -qx '# A template change' "$project/.gitignore" || fail 'the template change did not reach .gitignore, a managed file'
grep -qx '/scratch' "$project/.gitignore" || fail "the project's edit to .gitignore is gone"
grep -qx 'A line of the project.' "$project/README.md" || fail "the project's edit to README.md is gone"
! grep -qx 'A line of the template.' "$project/README.md" || fail 'the update changed README.md, a seeded file'
! grep -qx '// A template change' "$project/src/index.ts" || fail 'the update changed src/index.ts, a seeded file'
[[ -z $(find "$project" -name '*.rej' -print -quit) ]] || fail 'the update left a rejected hunk'
! grep -rq '^<<<<<<<' "$project" --exclude-dir=.git || fail 'the update left a conflict'

grep -qx '_commit: v100.0.1' "$work/app/.copier-answers.yml" || fail "the app's .copier-answers.yml does not record v100.0.1"
[[ ! -e $work/app/tests/playwright-version.test.ts ]] ||
  fail 'the update added back tests/playwright-version.test.ts, a managed file the project deleted'

member=$work/retrofit/packages/demo-retrofit
grep -qx '_commit: v100.0.1' "$work/retrofit/.copier-answers.yml" || fail "the retrofit's .copier-answers.yml does not record v100.0.1"
grep -qx '# A template change' "$work/retrofit/.gitignore" || fail "the template change did not reach the retrofit's .gitignore"
diff -r "$retrofit/packages/demo-retrofit/src" "$member/src" >&2 || fail "the update changed the retrofit's own src/"
grep -qx '// A template change' "$work/retrofit/tests/playwright-version.test.ts" ||
  fail "the template change did not reach the retrofit's tests/playwright-version.test.ts, a managed file"
[[ ! -e $member/tests ]] || fail 'the update added the starter unit test to the retrofit'
[[ ! -e $work/retrofit/tests/browser/home.spec.ts ]] || fail 'the update added the starter browser test to the retrofit'
[[ -z $(git -C "$work/retrofit" status --porcelain --untracked-files=all -- packages tests \
  ':!tests/playwright-version.test.ts') ]] || fail "the update changed the retrofit's packages/ or tests/"

grep -qx '_commit: v100.0.1' "$work/docs/.copier-answers.yml" || fail "the docs retrofit's .copier-answers.yml does not record v100.0.1"
grep -qx '# A template change' "$work/docs/.gitignore" || fail "the template change did not reach the docs retrofit's .gitignore"

grep -qx '_commit: v100.0.1' "$work/single/.copier-answers.yml" || fail "the single-package retrofit's .copier-answers.yml does not record v100.0.1"
grep -qx '# A template change' "$work/single/.gitignore" || fail "the template change did not reach the single-package retrofit's .gitignore"

# In every retrofit, the update changes managed files and neither adds a file nor deletes one
for repository in retrofit docs single; do
  files=$(git -C "$work/$repository" status --porcelain --untracked-files=all | grep -v '^ M ' || true)
  [[ -z $files ]] || fail "the update added or deleted files in the $repository retrofit: $files"
done
echo 'copier update: from the last release with its CI and its Pages deployment kept, managed file updated, project edits kept, seeded files left alone, the Playwright version test managed, no starter or layout files in a retrofit'
