<img src="./.github/assets/readme-header.svg" alt="whatsaaaa" width="100%" />

# template

Copier template, shared CI workflows and repository settings for whatsaaaa projects

## Reusable workflows

Call them at the floating major tag, `@v1`, which takes every fix and feature of that major. A
breaking change to an input comes with a new major.

| Workflow | What it runs | Inputs (default) |
| --- | --- | --- |
| [`node-ci.yml`](.github/workflows/node-ci.yml) | `check`: the package.json scripts in order, failing when `lint` auto-fixed a file. `browser`: the browser tests in the Playwright image, keeping the report of a failed run for 7 days | `scripts` (`format:check lint type-check test build`), `lint-fix-guard` (`true`), `timeout-minutes` (`15`), `playwright-version` (empty: no browser job), `browser-script` (`test:browser`), `node-version` (`24`), `working-directory` (`.`) |
| [`changesets-release.yml`](.github/workflows/changesets-release.yml) | changesets' Version Packages pull request, then pack and publish to npm by trusted publishing, in the `npm` environment | none |
| [`pages.yml`](.github/workflows/pages.yml) | builds a site with a package.json script and deploys it to GitHub Pages | `build-script` (`build`), `artifact-path` (required), `fetch-depth` (`1`; `0` for VitePress `lastUpdated`), `node-version` (`24`), `working-directory` (`.`) |

Each file starts with the caller it expects, the permissions to grant and the repository
settings it needs. A caller keeps its own `on:`, `concurrency` and project-specific jobs:

```yaml
jobs:
  ci:
    uses: whatsaaaa/template/.github/workflows/node-ci.yml@v1
    with:
      playwright-version: 1.65.0 # the version of @playwright/test
```

The checks of that job are named `ci / check` and `ci / browser`.

npm's trusted publisher names the calling workflow, so a project's release workflow stays
`.github/workflows/release.yml`.

## The setup action

[`.github/actions/setup`](.github/actions/setup/action.yml) is the step every job starts with
after `actions/checkout` (with `persist-credentials: false`): pnpm at the version of
`packageManager`, Node.js with the pnpm store cache, and `pnpm install --frozen-lockfile`.

```yaml
- uses: whatsaaaa/template/.github/actions/setup@v1
  with:
    node-version: '22' # inputs: node-version, working-directory, install, frozen-lockfile, cache
```

The workflows here call it as `$/.github/actions/setup`, which is this repository at the commit of
the running workflow, so a workflow and its action never come from different versions.

## Working on it

CI runs [actionlint](https://github.com/rhysd/actionlint) (with shellcheck) on every workflow and
calls `node-ci.yml` and the setup action on [`tests/fixtures/node-project`](tests/fixtures/node-project),
whose scripts fail when the job is set up wrong. A broken shared workflow fails here before a tag
moves.

Third-party actions are pinned by commit SHA with the version in a comment.

Releasing: tag the merge commit `vX.Y.Z` and move `vX` to it.
