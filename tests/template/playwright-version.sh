#!/usr/bin/env bash
# Checks the managed tests/playwright-version.test.ts of a rendered, installed project against the
# ways a project writes the version: it reads ci.yml as YAML, so a quoted version passes and one
# only in a comment fails, and it compares the version installed, so a range in package.json
# passes. Each change is undone before the next.
# Usage: tests/template/playwright-version.sh <project>
set -euo pipefail

project=$(cd "$1" && pwd)
ci=$project/.github/workflows/ci.yml
work=$(mktemp -d)
cp "$ci" "$project/package.json" "$work"
restore() { cp "$work/ci.yml" "$ci"; cp "$work/package.json" "$project/package.json"; rm -rf "$work"; }
trap restore EXIT
fail() { echo "::error::$1" >&2; exit 1; }
run_test() { (cd "$project" && pnpm exec vitest run tests/playwright-version.test.ts >"$work/vitest.log" 2>&1); }
# with_ci <lines>: ci.yml as rendered, its playwright-version line replaced by the lines (\n
# between them), each indented as it is
with_ci() {
  awk -v lines="$1" -v indent="$indent" '/^ *playwright-version: /{
    gsub(/\n/, "\n" indent, lines); print indent lines; next } { print }' "$work/ci.yml" >"$ci"
}

version=$(sed -n 's/^ *playwright-version: \(.*\)$/\1/p' "$work/ci.yml")
indent=$(sed -n 's/^\( *\)playwright-version: .*$/\1/p' "$work/ci.yml")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "ci.yml names no exact Playwright version: '$version'"

run_test || fail "the rendered project fails its Playwright version test: $(cat "$work/vitest.log")"

with_ci "playwright-version: '$version'"
run_test || fail "the Playwright version test fails a quoted version in ci.yml: $(cat "$work/vitest.log")"

with_ci "# playwright-version: $version\nplaywright-version: 0.0.1"
! run_test || fail 'the Playwright version test passes a version only in a comment of ci.yml'

with_ci "# playwright-version: $version"
! run_test || fail 'the Playwright version test passes a ci.yml whose version is commented out'

cp "$work/ci.yml" "$ci"
sed -e "s/\"@playwright\/test\": \"$version\"/\"@playwright\/test\": \"^${version%.*}.0\"/" \
  "$work/package.json" >"$project/package.json"
grep -qF "\"@playwright/test\": \"^${version%.*}.0\"" "$project/package.json" ||
  fail 'package.json names no exact version of @playwright/test to change into a range'
run_test || fail "the Playwright version test fails a range in package.json: $(cat "$work/vitest.log")"

echo 'playwright-version.test.ts: reads ci.yml as YAML and compares the installed version'
