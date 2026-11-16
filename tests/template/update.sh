#!/usr/bin/env bash
# Checks that `copier update`, run as Renovate runs it (no --trust), carries a template change
# into a managed file while keeping the project's own edit to it, and leaves a seeded file alone.
# Usage: tests/template/update.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git_quiet() { git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false "$@" >/dev/null; }
fail() { echo "::error::$1" >&2; exit 1; }

# The template as this checkout has it, uncommitted files included, released as v100.0.0
mkdir "$work/template"
git -C "$root" ls-files --cached --others --exclude-standard |
  while read -r file; do [[ -e $root/$file ]] && printf '%s\n' "$file"; done |
  tar -C "$root" -cf - -T - | tar -C "$work/template" -xf -
git_quiet -C "$work/template" init
git_quiet -C "$work/template" add -A
git_quiet -C "$work/template" commit -m v100.0.0
git_quiet -C "$work/template" tag v100.0.0

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

# v100.0.1 changes the same two files, and a seeded file the project kept as it was
echo '# A template change' >>"$work/template/template/.gitignore.jinja"
echo 'A line of the template.' >>"$work/template/template/README.md.jinja"
echo '// A template change' >>"$work/template/template/{{ package_dir }}/src/index.ts.jinja"
git_quiet -C "$work/template" commit -am v100.0.1
git_quiet -C "$work/template" tag v100.0.1

(cd "$work/project" && copier update --skip-answered --defaults --vcs-ref v100.0.1 --quiet)

project=$work/project
grep -qx '_commit: v100.0.1' "$project/.copier-answers.yml" || fail '.copier-answers.yml does not record v100.0.1'
grep -qx '# A template change' "$project/.gitignore" || fail 'the template change did not reach .gitignore, a managed file'
grep -qx '/scratch' "$project/.gitignore" || fail "the project's edit to .gitignore is gone"
grep -qx 'A line of the project.' "$project/README.md" || fail "the project's edit to README.md is gone"
! grep -qx 'A line of the template.' "$project/README.md" || fail 'the update changed README.md, a seeded file'
! grep -qx '// A template change' "$project/src/index.ts" || fail 'the update changed src/index.ts, a seeded file'
[[ -z $(find "$project" -name '*.rej' -print -quit) ]] || fail 'the update left a rejected hunk'
! grep -rq '^<<<<<<<' "$project" --exclude-dir=.git || fail 'the update left a conflict'
echo 'copier update: managed file updated, project edits kept, seeded files left alone'
