<img src="./.github/assets/readme-header.svg" alt="whatsaaaa" width="100%" />

# template

Copier template, shared CI workflows and repository settings for whatsaaaa projects

## Create a project

Every new project starts from the [Copier](https://copier.readthedocs.io) template here, with
Copier 9.15 or later. Give it the template's HTTPS URL, not SSH: `.copier-answers.yml` records it,
and Renovate, which has no SSH key, clones it from there. Name the latest tag:

```sh
copier copy --vcs-ref vX.Y.Z https://github.com/whatsaaaa/template.git my-project
```

It asks the questions of [`copier.yml`](copier.yml): name, description, visibility, the stack
(TypeScript on pnpm, or `base`, only the stack-neutral files), and for TypeScript the kind (library,
app or site), one package or a workspace, the starter files, CI, publishing to npm, the framework (none,
Vue, React, Astro), the design system, browser tests and GitHub Pages; then the README header's
brand kit, the license and `AGENTS.md`. `--data key=value` or `--data-file answers.yml` answers them up front, and
`--defaults` takes the default of the rest. A repository that only keeps code, never published to
npm nor deployed, answers no to CI: it gets no workflow, its settings require no status checks, and
like a `base` project it gets a `.no-mistakes.yaml` that tells no-mistakes there is no CI.
Publishing to npm and GitHub Pages run on CI, so without it Copier does not ask them and
refuses a yes given up front. Then, in the project:

```sh
pnpm install   # writes pnpm-lock.yaml, which CI installs from
git add -A     # .copier-answers.yml too: copier update reads it
```

The git remote stays SSH: `git@github.com:whatsaaaa/my-project.git`. The repository settings come
from [`settings/apply.sh`](settings/README.md), which reads the same answers.

Some files are **seeded**: rendered once, then the project's own, which an update leaves alone:
`README.md`, `AGENTS.md`, `package.json`, the starter `src/` and `tests/`, and the Vitest,
Playwright, Vite and Astro configs. Every other file is **managed**: an update carries the
template's changes into it, and keeps the project's own changes to it.

An existing repository moves onto the template the same way, rendered into its own checkout, with
`--data starter=false`. It is laid out its own way, which the template cannot know, so it gets none
of the seeded files that assume the template's layout: no `package.json`, no Vitest, Playwright,
Vite or Astro config, no `index.html` and no starter `src/` and `tests/`. It has its own wherever
its layout needs them. A seeded file is skipped only where it exists, so otherwise every update
would add back the ones it has no place for, such as `packages/<name>/package.json` for a
workspace whose packages have other names. Only `README.md`, `AGENTS.md` and
`tests/playwright-version.test.ts` are still seeded. A managed file it has no place for it deletes
once: an update does not add back a managed file the project deleted. A library without a docs
app can then still have browser tests of its own pages, such as playgrounds, with its own
Playwright config.

## Update a project

Renovate opens the update as a pull request when the template has a new tag: the shared preset turns
on its `copier` manager, which runs `copier update --skip-answered --defaults --vcs-ref <tag>`.
By hand, in the project, on a clean working tree:

```sh
copier update --skip-answered --vcs-ref vX.Y.Z
```

Copier renders the version the project came from and the new one, and applies the difference to the
project. Where the project changed the same lines, it leaves conflict markers to resolve. Without
`--skip-answered` it asks every question again, which is how a project changes an answer, such as
turning on browser tests. A new optional part of the template is a new question that defaults to
off, so an update never adds it unasked.

## Reusable workflows

Call them at the floating major tag, `@v1`, which takes every fix and feature of that major. A
breaking change to an input comes with a new major.

| Workflow | What it runs | Inputs (default) |
| --- | --- | --- |
| [`node-ci.yml`](.github/workflows/node-ci.yml) | `check`: the package.json scripts in order, failing when `lint` auto-fixed a file. `browser`: the browser tests in the Playwright image, keeping the report of a failed run for 7 days | `scripts` (`format:check lint type-check test build`), `lint-fix-guard` (`true`), `timeout-minutes` (`15`), `playwright-version` (empty: no browser job), `browser-script` (`test:browser`), `node-version` (`24`), `working-directory` (`.`) |
| [`changesets-release.yml`](.github/workflows/changesets-release.yml) | changesets' Version Packages pull request, then pack and publish to npm by trusted publishing, in the `npm` environment. Starts the caller's CI on the Version Packages pull request, which needs `workflow_dispatch` | `ci-workflow` (`ci.yml`) |
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

The Copier template is in five places:

- [`copier.yml`](copier.yml): the questions, and what each answer leaves out.
- [`template/`](template): the files Copier renders.
- [`includes/`](includes): the Jinja macros the templates import.
- [`package.json`](package.json): the versions a new project starts with, which Renovate keeps
  current. Nothing installs them here.
- [`brand/`](brand): each brand kit's README header, favicon and identity, copied from
  `@whatsaaaa/design-system` (`assets/<kit>/` of the package and `identity/` of the repository, at
  the same release). Never edit them here: a new kit or a changed one comes from the design system.

It takes no `_tasks`, `_migrations` or Jinja extensions: hosted Renovate runs `copier update` without
`--trust`, which would refuse them.

The Template workflow renders each case in [`tests/template/cases`](tests/template/cases), into a
copy of the folder of the same name when there is one (the repository a retrofit moves onto the
template, its `package.json` files on the versions of the catalog), and checks it as its own CI would: actionlint on its workflows, then, set up by the setup action, `format:check`,
`lint` (failing when it changed a file), `type-check`, `test` and `build`, and the browser tests.
actionlint cannot read a workflow called at `@v1`, so
[`tests/template/check-callers.py`](tests/template/check-callers.py) checks each call against the
workflows of the checkout: the inputs it passes, the permissions it grants, and the CI workflow the
release starts on the Version Packages pull request.
[`tests/template/update.sh`](tests/template/update.sh) checks `copier update` with the oldest Copier
`copier.yml` allows and the current one, from the last release too, whose tag a clone needs
(`git fetch --tags`), and [`tests/template/no-ci.sh`](tests/template/no-ci.sh)
checks a project without CI: no workflow and nothing naming one, a `.no-mistakes.yaml`, and
publishing or GitHub Pages neither asked nor taken. To try a case locally:

```sh
tests/template/render.sh vue-app /tmp/vue-app   # renders this checkout, uncommitted changes too
```

A rendered project's own CI calls the reusable workflows at `@v1`, so the Template workflow runs the
same scripts itself: `node-ci.yml` checks out the repository that calls it, which has no rendered
project in it.

Third-party actions are pinned by commit SHA with the version in a comment.

## Releasing

Tag the squash commit with an annotated tag, push it, and move the floating major tag to the same
commit as a lightweight tag:

```sh
git tag -a vX.Y.Z -m vX.Y.Z <commit>
git tag -f vX <commit>
git push origin vX.Y.Z
git push --force origin vX
```

Copier records the version a project came from as `_commit` in `.copier-answers.yml`, from
`git describe --tags`, which prefers an annotated tag to a lightweight one. With every tag
lightweight, it records the floating `vX`, which names a different commit at each release: the next
`copier update` then sees no change to carry, or refuses it as a downgrade. So release tags are
always annotated, and `vX` stays lightweight.
