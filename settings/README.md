<img src="../.github/assets/readme-header.svg" alt="whatsaaaa" width="100%" />

# Repository settings

`apply.sh` gives a whatsaaaa repository the shared GitHub settings, the ones no file in the repository can carry: merge options, the `main` ruleset, environments, security toggles, Pages and labels. With `--check` it only reads, and prints how the repository differs.

```sh
settings/apply.sh whatsaaaa/<name> --check   # report, change nothing
settings/apply.sh whatsaaaa/<name>           # apply
```

It needs `gh` (signed in with admin rights on the repository) and `jq`. It is idempotent: it writes only what differs, so a second run reports `0 fixed`. Exit status: 0 in line or applied, 1 drift found by `--check`, 2 usage or API error.

The drift report over the whole account:

```sh
gh repo list whatsaaaa --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' |
  while read -r repo; do settings/apply.sh "$repo" --check; done
```

## What it sets

| Area | Every repository | When an answer turns it on |
| --- | --- | --- |
| Metadata | `description` from the answers | `homepage`: the Pages URL when `pages` |
| Features | issues on; wiki, projects and discussions off | |
| Merging | squash merges only, titled with the pull request title and carrying the commit messages; delete branch on merge on, update branch on, auto-merge off | |
| Actions | default `GITHUB_TOKEN` read-only | Actions may create and approve pull requests when `publish` (changesets opens the Version Packages pull request) |
| Security | public repositories: secret scanning, push protection, Dependabot alerts and private vulnerability reporting on | |
| Rulesets | public repositories: `main` from [`rulesets/main.json`](rulesets/main.json): no deletion, no force-push, signed commits, pull requests with 0 approvals and squash merges only, no bypass | required status checks: `ci / check` when `stack` is `typescript` and `ci` is not `false`, plus `ci / browser` with `browser_tests` |
| Pages | | `build_type: workflow` when `pages` |
| Environments | | `npm` ([`environments/npm.json`](environments/npm.json): reviewer `whatsaaaa`, deployments from `main`) when `publish`; `github-pages` (deployments from `main`) when `pages` |
| Labels | the ten in [`labels.json`](labels.json); labels a repository adds itself are left alone | |

The JSON files are the REST request bodies, so a change to them is reviewed as exactly what GitHub receives. The ruleset's required status checks rule is the one part added by the script, from the answers. Areas a repository does not use are left alone: the script never deletes a ruleset, an environment or a label it does not manage. Inside an environment it manages, it does remove deployment branch policies that the JSON file does not list.

Private repositories skip security and rulesets: on GitHub Free, rulesets are not enforced on private repositories and environments there cannot have reviewers. Run the script again when a repository goes public.

## Answers

The script reads the repository's `.copier-answers.yml` through the contents API, so it needs no clone. Visibility comes from GitHub, not the answers. Until a repository is rendered from the template, its answers live in `answers/<name>.yml`, in the same format, and that file goes once the repository has `.copier-answers.yml`. Two flags override either source for one run:

| Flag | Effect |
| --- | --- |
| `--answers <file>` | answers from a YAML file, merged over the repository's |
| `--set <key>=<value>` | one answer, repeatable; the value is YAML (`--set publish=false`) |

The answers it reads are `description`, `publish`, `pages`, `stack`, `ci` and `browser_tests`; answers without `ci`, from before the template asked it, mean CI. `required_checks` (a list of check names) is a settings-only answer for repositories whose CI does not call the shared workflows yet; it replaces the derived check names. A rendered repository whose CI runs more checks than the defaults lists them in its override instead.

## Overrides

`overrides/<name>.json` is merged last over the desired state, for what is deliberate in one repository:

| Repository | Override | Why |
| --- | --- | --- |
| dotfiles | `pull_request_creation_policy: collaborators_only` | its README says it does not take pull requests |
| form-builder | `required_checks`: `ci / check` and its own jobs | its CI runs coverage, docs, packages, minimum-version and consumer jobs beyond the shared defaults |
| whatsaaaa | `has_issues: false` | the profile repository has no issues |

The desired state has the keys `repository` (the `PATCH /repos` body), `topics`, `actions`, `security`, `rulesets`, `environments`, `pages` and `labels`; a `null` value in an override stops the script managing that key. An override's top-level `required_checks` (a list of check names) is not merged: like the answer of that name, which it takes precedence over, it replaces the derived check names in the `main` ruleset.

## Tests

```sh
settings/test/run.sh          # apply.sh against recorded API responses, no network
UPDATE=1 settings/test/run.sh # rewrite test/expected/ after a deliberate change
settings/test/record.sh whatsaaaa/<name> settings/test/fixtures/<name>.json
```

`test/bin/gh` stands in for `gh api`: it answers from a fixture and logs every request, and the expected output of each case lists the writes the script made. Recording only sends GET requests. CI runs the tests and `shellcheck`.
