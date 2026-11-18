#!/usr/bin/env bash
# Apply the shared repository settings to one GitHub repository, or report how
# it differs from them with --check. See settings/README.md.
#
# Usage: settings/apply.sh <owner/name> [--check] [--answers <file>] [--set <key>=<value>]...
#
# Exit status: 0 in line (or applied), 1 drift found by --check, 2 usage or API error.

set -euo pipefail

SETTINGS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  sed -n '5p' "${BASH_SOURCE[0]}" | sed 's/^# //' >&2
  exit 2
}

die() {
  printf 'apply.sh: %s\n' "$*" >&2
  exit 2
}

repo=''
check=false
answers_file=''
sets=()
while (($#)); do
  case $1 in
    --check) check=true ;;
    --answers)
      (($# >= 2)) || usage
      answers_file=$2
      shift
      ;;
    --set)
      (($# >= 2)) || usage
      [[ $2 == *=* ]] || die "--set needs <key>=<value>, got '$2'"
      sets+=("$2")
      shift
      ;;
    -h | --help) usage ;;
    -*) die "unknown option '$1'" ;;
    *)
      [[ -z $repo ]] || usage
      repo=$1
      ;;
  esac
  shift
done
[[ $repo =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || usage
name=${repo#*/}

command -v gh >/dev/null || die 'gh is not installed'
command -v jq >/dev/null || die 'jq is not installed'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- GitHub API -------------------------------------------------------------

# api <method> <path> [<body file>] [<header>]: the response body goes to
# $work/body and the HTTP status to $status (204 for a success without a body).
# Under --check every request that is not a GET is refused, so a check can
# never change a setting.
status=0
api() {
  local method=$1 path=$2 input=${3-} header=${4-}
  if $check && [[ $method != GET ]]; then
    die "refusing $method $path under --check"
  fi
  local args=(api -X "$method" "$path")
  [[ -n $input ]] && args+=(--input "$input")
  [[ -n $header ]] && args+=(-H "$header")
  if gh "${args[@]}" >"$work/body" 2>"$work/err"; then
    if [[ -s $work/body ]]; then status=200; else status=204; fi
  else
    status=$(grep -oE 'HTTP [0-9]{3}' "$work/err" | tail -n 1 | cut -d ' ' -f 2 || true)
    status=${status:-0}
  fi
}

# get <path> [<allowed status>...]: like api GET, but any status other than a
# success or one of the allowed ones is fatal.
get() {
  local path=$1 code
  shift
  api GET "$path"
  [[ $status == 200 || $status == 204 ]] && return 0
  for code in "$@"; do [[ $status == "$code" ]] && return 0; done
  die "GET $path failed (HTTP $status): $(head -c 300 "$work/err")"
}

# send <method> <path> [<json>]: a write that must succeed.
send() {
  local method=$1 path=$2 body=${3-}
  if [[ -n $body ]]; then
    printf '%s' "$body" >"$work/input"
    api "$method" "$path" "$work/input"
  else
    api "$method" "$path"
  fi
  [[ $status == 200 || $status == 201 || $status == 204 ]] ||
    die "$method $path failed (HTTP $status): $(head -c 300 "$work/err")"
}

# --- Report -----------------------------------------------------------------

drifted=0

# report <area> <drift json lines>: prints each difference, or "ok <area>".
report() {
  local area=$1 lines=$2 verb=drift
  $check || verb=fix
  if [[ -z $lines ]]; then
    printf '  %-6s %s\n' ok "$area"
    return
  fi
  while IFS= read -r line; do
    drifted=$((drifted + 1))
    printf '  %-6s %s\n' "$verb" "$(jq -r '"\(.path): \(.have) -> \(.want)"' <<<"$line")"
  done <<<"$lines"
}

note() { printf '  %-6s %s\n' "$1" "$2"; }

# Shared jq: drift(path; want; have) compares only the keys the desired state
# names, so fields GitHub adds to its responses are never drift.
# shellcheck disable=SC2016 # a jq program, not shell
JQ_LIB='
def show: if . == null then "absent" else tojson end;
def drift($path; $want; $have):
  if ($want | type) == "object" and ($have | type) == "object" then
    $want | to_entries[] | . as $e | drift($path + "." + $e.key; $e.value; $have[$e.key])
  elif $want == $have then empty
  else {path: $path, want: ($want | show), have: ($have | show)} end;
'

# diff_json <path> <want json> <have json>: one drift object per line.
diff_json() {
  jq -nc --arg path "$1" --argjson want "$2" --argjson have "$3" \
    "$JQ_LIB"'drift($path; $want; $have)'
}

# --- Answers ----------------------------------------------------------------

# yaml_to_json: the flat subset of YAML that Copier writes to
# .copier-answers.yml (scalars and lists of scalars at the top level) as one
# JSON object. Nested mappings are skipped; the script reads none.
yaml_to_json() {
  awk '
    function esc(s) {
      gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s)
      return "\"" s "\""
    }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # quoted(s): the text of a quoted scalar up to its closing quote, unescaped;
    # anything after it can only be a comment.
    function quoted(s,   q, i, c, out) {
      q = substr(s, 1, 1); out = ""
      for (i = 2; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q == "\"" && c == "\\") { i++; out = out substr(s, i, 1); continue }
        if (c == q) {
          if (q == "\047" && substr(s, i + 1, 1) == q) { out = out q; i++; continue }
          return out
        }
        out = out c
      }
      return out
    }
    function scalar(s) {
      s = trim(s)
      if (s ~ /^["\047]/) return esc(quoted(s))
      sub(/[ \t]+#.*$/, "", s)
      if (s ~ /^(true|True|TRUE)$/) return "true"
      if (s ~ /^(false|False|FALSE)$/) return "false"
      if (s ~ /^(null|Null|NULL|~)?$/) return "null"
      if (s ~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/) return s
      return esc(s)
    }
    function flow(s,   n, i, parts, out) {
      s = trim(s); s = substr(s, 2, length(s) - 2)
      if (trim(s) == "") return "[]"
      n = split(s, parts, ",")
      out = ""
      for (i = 1; i <= n; i++) out = out (i > 1 ? "," : "") scalar(parts[i])
      return "[" out "]"
    }
    function flush() {
      if (key == "") return
      if (mode == "list") print "[" esc(key) ",[" items "]]"
      else if (mode == "empty") print "[" esc(key) ",null]"
      key = ""; mode = ""; items = ""
    }
    /^[ \t]*(#.*)?$/ || /^---/ { next }
    /^[A-Za-z_][A-Za-z0-9_-]*:([ \t]|$)/ {
      flush()
      k = $0; sub(/:.*/, "", k)
      v = $0; sub(/^[^:]*:/, "", v); v = trim(v)
      if (v == "") { key = k; mode = "empty"; items = ""; next }
      if (v ~ /^\[.*\]$/) print "[" esc(k) "," flow(v) "]"
      else print "[" esc(k) "," scalar(v) "]"
      next
    }
    /^[ \t]*- / {
      if (key == "" || mode == "nested") next
      v = $0; sub(/^[ \t]*- /, "", v)
      items = items (mode == "list" ? "," : "") scalar(v)
      mode = "list"
      next
    }
    { if (key != "" && mode == "empty") mode = "nested" }
    END { flush() }
  ' | jq -s 'map({(.[0]): .[1]}) | add // {}'
}

answers='{}'
answers_source='none'
api GET "repos/$repo/contents/.copier-answers.yml" '' 'Accept: application/vnd.github.raw+json'
if [[ $status == 200 ]]; then
  answers=$(yaml_to_json <"$work/body")
  answers_source='.copier-answers.yml'
elif [[ $status == 404 ]]; then
  if [[ -f $SETTINGS_DIR/answers/$name.yml ]]; then
    answers=$(yaml_to_json <"$SETTINGS_DIR/answers/$name.yml")
    answers_source="settings/answers/$name.yml"
  fi
else
  die "GET repos/$repo/contents/.copier-answers.yml failed (HTTP $status)"
fi
if [[ -n $answers_file ]]; then
  [[ -f $answers_file ]] || die "no answers file '$answers_file'"
  answers=$(jq -s '.[0] * .[1]' <(printf '%s' "$answers") <(yaml_to_json <"$answers_file"))
  answers_source="$answers_source + ${answers_file##*/}"
fi
for pair in ${sets[@]+"${sets[@]}"}; do
  answers=$(jq -s '.[0] * .[1]' <(printf '%s' "$answers") \
    <(printf '%s: %s\n' "${pair%%=*}" "${pair#*=}" | yaml_to_json))
  answers_source="$answers_source + --set ${pair%%=*}"
done

# --- Desired state ----------------------------------------------------------

get "repos/$repo"
repo_json=$(cat "$work/body")
visibility=$(jq -r .visibility <<<"$repo_json")

if [[ $name == "${repo%%/*}.github.io" ]]; then
  pages_url="https://$name/"
else
  pages_url="https://${repo%%/*}.github.io/$name/"
fi

overrides='{}'
if [[ -f $SETTINGS_DIR/overrides/$name.json ]]; then
  overrides=$(jq . "$SETTINGS_DIR/overrides/$name.json")
fi

# Areas a repository does not use are absent; null values are unmanaged keys.
desired=$(jq -n \
  --argjson a "$answers" \
  --argjson overrides "$overrides" \
  --arg visibility "$visibility" \
  --arg pages_url "$pages_url" \
  --slurpfile ruleset "$SETTINGS_DIR/rulesets/main.json" \
  --slurpfile labels "$SETTINGS_DIR/labels.json" \
  --slurpfile npm "$SETTINGS_DIR/environments/npm.json" \
  --slurpfile npm_branches "$SETTINGS_DIR/environments/npm.branch-policies.json" \
  --slurpfile gh_pages "$SETTINGS_DIR/environments/github-pages.json" \
  --slurpfile gh_pages_branches "$SETTINGS_DIR/environments/github-pages.branch-policies.json" '
  ($a.publish == true) as $publish
  | ($a.pages == true) as $pages
  | ($a.required_checks // (
      if ($a.stack // "") == "typescript" then
        ["ci / check"] + (if $a.browser_tests == true then ["ci / browser"] else [] end)
      else [] end)) as $checks
  | {
      repository: {
        description: $a.description,
        homepage: (if $pages then $pages_url else null end),
        has_issues: true,
        has_wiki: false,
        has_projects: false,
        has_discussions: false,
        allow_merge_commit: false,
        allow_squash_merge: true,
        allow_rebase_merge: false,
        squash_merge_commit_title: "PR_TITLE",
        squash_merge_commit_message: "COMMIT_MESSAGES",
        delete_branch_on_merge: true,
        allow_update_branch: true,
        allow_auto_merge: false
      },
      actions: {
        default_workflow_permissions: "read",
        can_approve_pull_request_reviews: $publish
      },
      security: (if $visibility == "public" then {
        secret_scanning: "enabled",
        secret_scanning_push_protection: "enabled",
        vulnerability_alerts: true,
        private_vulnerability_reporting: true
      } else null end),
      rulesets: {
        main: ($ruleset[0] | .rules += (if $checks == [] then [] else [{
          type: "required_status_checks",
          parameters: {
            strict_required_status_checks_policy: false,
            do_not_enforce_on_create: false,
            required_status_checks: ($checks | map({context: .}))
          }
        }] end))
      },
      environments: ({}
        + (if $publish then {npm: {body: $npm[0], branch_policies: $npm_branches[0]}} else {} end)
        + (if $pages then {"github-pages": {body: $gh_pages[0], branch_policies: $gh_pages_branches[0]}} else {} end)),
      pages: (if $pages then {build_type: "workflow"} else null end),
      labels: $labels[0]
    }
  | . * $overrides
  | walk(if type == "object" then with_entries(select(.value != null)) else . end)
')

printf '%s (%s, answers: %s)\n' "$repo" "$visibility" "$answers_source"

# --- Repository: metadata, features, merging --------------------------------

area_repository() {
  local want have lines body
  want=$(jq '.repository' <<<"$desired")
  have=$repo_json
  lines=$(diff_json repository "$want" "$have")
  if ! $check && [[ -n $lines ]]; then
    body=$(jq -n --argjson want "$want" --argjson have "$have" \
      '$want | with_entries(select(.value != $have[.key]))')
    send PATCH "repos/$repo" "$body"
  fi
  report repository "$lines"
}

area_topics() {
  jq -e 'has("topics")' <<<"$desired" >/dev/null || return 0
  local want have lines
  want=$(jq '.topics | sort' <<<"$desired")
  have=$(jq '.topics // [] | sort' <<<"$repo_json")
  lines=$(diff_json topics "$want" "$have")
  if ! $check && [[ -n $lines ]]; then
    send PUT "repos/$repo/topics" "$(jq -n --argjson names "$want" '{names: $names}')"
  fi
  report topics "$lines"
}

# --- Actions ----------------------------------------------------------------

area_actions() {
  local want lines
  want=$(jq '.actions' <<<"$desired")
  get "repos/$repo/actions/permissions/workflow"
  lines=$(diff_json actions "$want" "$(cat "$work/body")")
  if ! $check && [[ -n $lines ]]; then
    send PUT "repos/$repo/actions/permissions/workflow" "$want"
  fi
  report actions "$lines"
}

# --- Security (public repositories) -----------------------------------------

area_security() {
  if ! jq -e 'has("security")' <<<"$desired" >/dev/null; then
    note skip "security: $visibility repository"
    return 0
  fi
  local want have alerts reporting lines body
  want=$(jq '.security' <<<"$desired")
  get "repos/$repo/vulnerability-alerts" 404
  if [[ $status == 204 ]]; then alerts=true; else alerts=false; fi
  get "repos/$repo/private-vulnerability-reporting"
  reporting=$(jq '.enabled' "$work/body")
  have=$(jq --argjson alerts "$alerts" --argjson reporting "$reporting" '{
    secret_scanning: .security_and_analysis.secret_scanning.status,
    secret_scanning_push_protection: .security_and_analysis.secret_scanning_push_protection.status,
    vulnerability_alerts: $alerts,
    private_vulnerability_reporting: $reporting
  }' <<<"$repo_json")
  lines=$(diff_json security "$want" "$have")
  if ! $check && [[ -n $lines ]]; then
    body=$(jq -n --argjson want "$want" --argjson have "$have" '
      [("secret_scanning", "secret_scanning_push_protection")
        | select($want[.] != null and $want[.] != $have[.])
        | {(.): {status: $want[.]}}] | add
      | if . == null then empty else {security_and_analysis: .} end')
    [[ -z $body ]] || send PATCH "repos/$repo" "$body"
    if [[ $(jq -r '.vulnerability_alerts' <<<"$want") == true && $alerts == false ]]; then
      send PUT "repos/$repo/vulnerability-alerts"
    fi
    if [[ $(jq -r '.private_vulnerability_reporting' <<<"$want") == true && $reporting != true ]]; then
      send PUT "repos/$repo/private-vulnerability-reporting"
    fi
  fi
  report security "$lines"
}

# --- Rulesets ---------------------------------------------------------------

# GitHub Free does not enforce rulesets on private repositories, so they are
# only managed on public ones.
JQ_RULESET='
def norm: {
  name, target, enforcement, conditions,
  bypass_actors: ((.bypass_actors // []) | map({actor_id, actor_type, bypass_mode})
    | sort_by(.actor_type, .actor_id)),
  rules: ((.rules // []) | map({key: .type, value: ((.parameters // {})
    | if has("required_status_checks") then .required_status_checks |= (map(.context) | sort) else . end
    | if has("allowed_merge_methods") then .allowed_merge_methods |= sort else . end)})
    | from_entries)
};
'

area_rulesets() {
  if [[ $visibility != public ]]; then
    note skip "rulesets: not enforced on $visibility repositories on GitHub Free"
    return 0
  fi
  local rname want id lines
  get "repos/$repo/rulesets?includes_parents=false&per_page=100"
  local list
  list=$(cat "$work/body")
  for rname in $(jq -r '.rulesets | keys[]' <<<"$desired"); do
    want=$(jq --arg n "$rname" '.rulesets[$n]' <<<"$desired")
    id=$(jq -r --arg n "$rname" \
      'map(select(.name == $n and .source_type == "Repository")) | first | .id // empty' <<<"$list")
    if [[ -z $id ]]; then
      lines=$(jq -nc --arg p "rulesets.$rname" '{path: $p, have: "absent", want: "present"}')
      $check || send POST "repos/$repo/rulesets" "$want"
    else
      get "repos/$repo/rulesets/$id"
      lines=$(jq -nc --arg p "rulesets.$rname" --argjson want "$want" --slurpfile have "$work/body" \
        "$JQ_LIB$JQ_RULESET"'
        ($want | norm) as $w | ($have[0] | norm) as $h
        | drift($p; $w; $h),
          (($h.rules | keys) - ($w.rules | keys) | .[]
            | {path: ($p + ".rules." + .), have: "present", want: "absent"})')
      if ! $check && [[ -n $lines ]]; then
        send PUT "repos/$repo/rulesets/$id" "$want"
      fi
    fi
    report "rulesets.$rname" "$lines"
  done
}

# --- Environments -----------------------------------------------------------

area_environments() {
  local env want policies have lines
  for env in $(jq -r '.environments // {} | keys[]' <<<"$desired"); do
    want=$(jq --arg e "$env" '.environments[$e].body' <<<"$desired")
    policies=$(jq -c --arg e "$env" '.environments[$e].branch_policies' <<<"$desired")
    if [[ $visibility != public ]] && jq -e '.reviewers // [] | length > 0' <<<"$want" >/dev/null; then
      note skip "environments.$env.reviewers: not available on $visibility repositories on GitHub Free"
      want=$(jq 'del(.reviewers, .prevent_self_review)' <<<"$want")
    fi
    get "repos/$repo/environments/$env" 404
    if [[ $status == 404 ]]; then
      lines=$(jq -nc --arg p "environments.$env" '{path: $p, have: "absent", want: "present"}')
      if ! $check; then
        send PUT "repos/$repo/environments/$env" "$want"
        while IFS= read -r policy; do
          send POST "repos/$repo/environments/$env/deployment-branch-policies" "$policy"
        done < <(jq -c '.[]' <<<"$policies")
      fi
      report "environments.$env" "$lines"
      continue
    fi
    have=$(jq '
      (.protection_rules // []) as $rules
      | ($rules | map(select(.type == "required_reviewers")) | first) as $reviewers
      | {
          wait_timer: (($rules | map(select(.type == "wait_timer")) | first | .wait_timer) // 0),
          prevent_self_review: ($reviewers.prevent_self_review // false),
          reviewers: (($reviewers.reviewers // []) | map({type, id: .reviewer.id})),
          deployment_branch_policy
        }' "$work/body")
    lines=$(diff_json "environments.$env" "$want" "$have")
    if ! $check && [[ -n $lines ]]; then
      send PUT "repos/$repo/environments/$env" "$want"
    fi
    report "environments.$env" "$lines"

    get "repos/$repo/environments/$env/deployment-branch-policies?per_page=100"
    local actual missing extra
    actual=$(jq -c '.branch_policies | map({id, name, type: (.type // "branch")})' "$work/body")
    missing=$(jq -c --argjson have "$actual" \
      '.[] | select(. as $p | $have | map({name, type}) | index($p) | not)' <<<"$policies")
    extra=$(jq -c --argjson want "$policies" \
      '.[] | select({name, type} as $p | $want | index($p) | not)' <<<"$actual")
    lines=$(
      [[ -z $missing ]] || jq -c --arg p "environments.$env.branch_policies" \
        '{path: "\($p).\(.type):\(.name)", have: "absent", want: "present"}' <<<"$missing"
      [[ -z $extra ]] || jq -c --arg p "environments.$env.branch_policies" \
        '{path: "\($p).\(.type):\(.name)", have: "present", want: "absent"}' <<<"$extra"
    )
    if ! $check; then
      if [[ -n $missing ]]; then
        while IFS= read -r policy; do
          send POST "repos/$repo/environments/$env/deployment-branch-policies" "$policy"
        done <<<"$missing"
      fi
      if [[ -n $extra ]]; then
        while IFS= read -r policy; do
          send DELETE "repos/$repo/environments/$env/deployment-branch-policies/$(jq -r .id <<<"$policy")"
        done <<<"$extra"
      fi
    fi
    report "environments.$env.branch_policies" "$lines"
  done
}

# --- Pages ------------------------------------------------------------------

area_pages() {
  jq -e 'has("pages")' <<<"$desired" >/dev/null || return 0
  local want lines
  want=$(jq '.pages' <<<"$desired")
  get "repos/$repo/pages" 404
  if [[ $status == 404 ]]; then
    lines=$(jq -nc '{path: "pages", have: "absent", want: "present"}')
    $check || send POST "repos/$repo/pages" "$want"
  else
    lines=$(diff_json pages "$want" "$(cat "$work/body")")
    if ! $check && [[ -n $lines ]]; then
      send PUT "repos/$repo/pages" "$want"
    fi
  fi
  report pages "$lines"
}

# --- Labels -----------------------------------------------------------------

# Missing labels are created and differing ones updated; labels a repository
# adds for itself are left alone.
area_labels() {
  local want actual lines extra label
  want=$(jq -c '.labels' <<<"$desired")
  get "repos/$repo/labels?per_page=100"
  actual=$(jq -c 'map({name, color, description})' "$work/body")
  lines=$(jq -nc --argjson want "$want" --argjson have "$actual" "$JQ_LIB"'
    $want[] | . as $w | ($have | map(select(.name == $w.name)) | first) as $h
    | if $h == null then {path: "labels.\($w.name)", have: "absent", want: "present"}
      else drift("labels.\($w.name)"; $w | del(.name); $h) end')
  if ! $check && [[ -n $lines ]]; then
    while IFS= read -r label; do
      if jq -e --arg n "$(jq -r .name <<<"$label")" 'map(.name) | index($n)' <<<"$actual" >/dev/null; then
        send PATCH "repos/$repo/labels/$(jq -r '.name | @uri' <<<"$label")" "$(jq -c 'del(.name)' <<<"$label")"
      else
        send POST "repos/$repo/labels" "$label"
      fi
    done < <(jq -c --argjson have "$actual" '.[] | select(. as $w | $have | index($w) | not)' <<<"$want")
  fi
  report labels "$lines"
  extra=$(jq -r --argjson want "$want" 'map(.name) - ($want | map(.name)) | join(", ")' <<<"$actual")
  [[ -z $extra ]] || note note "labels: left alone: $extra"
}

area_repository
area_topics
area_actions
area_security
area_rulesets
area_pages
area_environments
area_labels

if $check; then
  printf '  %d drifted\n' "$drifted"
  ((drifted == 0)) || exit 1
else
  printf '  %d fixed\n' "$drifted"
fi
