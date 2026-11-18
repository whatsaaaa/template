#!/usr/bin/env bash
# Record the GET responses `apply.sh <owner/name> --check` reads, as a test
# fixture. Only GET requests reach GitHub; the fake gh refuses anything else.
#
# Usage: settings/test/record.sh <owner/name> <fixture.json>

set -euo pipefail

(($# == 2)) || {
  sed -n '5p' "${BASH_SOURCE[0]}" | sed 's/^# //' >&2
  exit 2
}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
real=$(command -v gh)
fixture=$2
echo '{}' >"$fixture"

FAKE_GH_RECORD=1 FAKE_GH_REAL=$real FAKE_GH_RESPONSES=$fixture PATH="$here/bin:$PATH" \
  "$here/../apply.sh" "$1" --check >/dev/null || true

# Keep the fields the script reads, so a fixture stays small and reviewable.
jq --arg repo "GET repos/$1" '
  with_entries(
    if .key == $repo then
      .value.body |= {name, full_name, visibility, description, homepage, topics,
        has_issues, has_wiki, has_projects, has_discussions, allow_merge_commit,
        allow_squash_merge, allow_rebase_merge, squash_merge_commit_title,
        squash_merge_commit_message, delete_branch_on_merge,
        allow_update_branch, allow_auto_merge, pull_request_creation_policy,
        security_and_analysis}
    elif (.key | test("/labels[?]")) then
      .value.body |= map({name, color, description})
    elif (.key | test("/environments/[^/]+$")) then
      .value.body.protection_rules |= (if . == null then . else map(
        if has("reviewers") then .reviewers |= map(.reviewer |= {login, id, type}) else . end) end)
    else . end)' "$fixture" >"$fixture.new"
mv "$fixture.new" "$fixture"
