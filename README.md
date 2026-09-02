# Caltech Library shared workflows

Reusable GitHub Actions workflows, the composite actions behind them, and the
shell scripts those actions run.

A repository **references** this logic rather than copying it. A fix made here
reaches every repository on its next run, and no file is ever written into your
working tree.

## The shape

Documentation generators disagree about a lot, but they all turn a source
directory into a directory of HTML. So the pipeline splits exactly there:

```
build (per generator)  →  index (optional)  →  deploy (shared)
```

Only the first step varies. That is what makes changing generators a contained
decision instead of a rewrite.

| Action | What it does |
| --- | --- |
| `build-pandoc` | Markdown → HTML with Pandoc and the shared Caltech theme |
| `build-zensical` | Markdown → HTML with [Zensical](https://zensical.org/) |
| `build-sphinx` | Sphinx, using the project's own documentation requirements |
| `index-site` | Pagefind search index over built HTML — works with any generator |
| `deploy-site` | Checks the build produced a real site, uploads it for Pages |
| `publish-to-s3` | Uploads built assets to S3 over OIDC and invalidates CloudFront |

Adding a generator means one new `build-*` action; nothing downstream changes.

## Quick start

Put your Markdown in `docs/`, then add `.github/workflows/docs.yml`:

```yaml
name: Docs

on:
  push:
    branches: [main]
  pull_request:

jobs:
  docs:
    uses: caltechlibrary/workflows/.github/workflows/docs-pandoc.yml@v1
    permissions:
      contents: read
      pages: write
      id-token: write
```

Then set **Settings → Pages → Source** to *GitHub Actions*. Nothing is
published until an admin does that.

`docs/README.md` becomes the site's `index.html`. Pull requests build the site
but do not deploy it.

### Inputs for `docs-pandoc.yml`

| Name | Default | What it does |
| --- | --- | --- |
| `docs-dir` | `docs` | Directory holding the Markdown sources |
| `extra-sources` | — | Markdown outside `docs-dir` to render too, one path or glob per line |
| `include` | — | Files or directories to copy into the site verbatim, one per line |
| `template` | shared theme | Pandoc template; point at a file in your repo to override |
| `lua-filters` | shared filters | One path per line. **Replaces** the defaults rather than adding to them |
| `index-from` | `README` | Basename whose page becomes `index.html` |
| `pre-build` | — | Shell command to run before rendering, e.g. `deno task build` |
| `pagefind` | `true` | Build a Pagefind search index |
| `runs-on` | `ubuntu-latest` | Runner label |

## Building the pipeline yourself

The reusable workflow is a convenience. When you need control over the steps —
a toolchain to install first, a different generator, your own deploy target —
assemble the actions in your own job and keep everything you are not changing:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-node@v6          # whatever your build needs
      - run: npm run build

      - uses: caltechlibrary/workflows/.github/actions/build-zensical@v1
      - uses: caltechlibrary/workflows/.github/actions/deploy-site@v1
```

Dropping the shared workflow and writing your own job is a normal, supported
choice. It is better than growing an input for every special case until the
shared thing serves nobody well.

### Sphinx

`build-sphinx` installs from your project's own requirements file and builds
with `sphinx-build`. Dependencies stay yours — Sphinx is sensitive to extension
and theme versions, so nothing is pinned centrally:

```yaml
- uses: caltechlibrary/workflows/.github/actions/build-sphinx@v1
  with:
    requirements: requirements-dev.txt
    python-version: "3.11"
- uses: caltechlibrary/workflows/.github/actions/deploy-site@v1
```

Two things it does differently from the hand-written Sphinx workflows in the
org. `setup-python`'s built-in `cache: pip` replaces the upgrade-pip /
pip-cache-dir / `actions/cache` sequence those carry. And the build writes
straight to the output directory rather than `docs/_build/html`, so build
output never lands in the source tree.

If you are moving off `peaceiris/actions-gh-pages`, `deploy-site` puts you on
the Pages artifact flow and the `gh-pages` branch stops being needed.

### Zensical

`build-zensical` reads `zensical.toml` **or** `mkdocs.yml`, so a project coming
from MkDocs can point it at the config it already has. Zensical ships its own
search, so `index-site` is unnecessary.

The version is pinned by default, and you should raise it deliberately.
Zensical is pre-1.0 and releasing every few days; an unpinned install means
absorbing a release nobody chose.

Note that Zensical writes directory-style URLs — `second/index.html`, not
`second.html`. Links between pages differ from the Pandoc output, which matters
if you are migrating an existing site.

## Action reference

Every build action writes a directory of static HTML to `output` with an
`index.html` at its root. That is the only thing the rest of the pipeline
depends on, which is why swapping generators is a one-action change.

**A build action's `output` and `deploy-site`'s `path` must be the same
directory.** Both default to `_site`, so the coupling is invisible until you
change one — change the other too. By contrast, `prefix` and the path in
`public-base-url` need not correspond at all; they match in some deployments by
coincidence.

### `build-pandoc`

| Input | Default | |
| --- | --- | --- |
| `docs-dir` | `docs` | Markdown sources |
| `output` | `_site` | Where the site is written |
| `extra-sources` | — | Markdown outside `docs-dir`, one path or glob per line |
| `include` | — | Files or directories copied in verbatim, one per line |
| `template` | shared theme | Pandoc template; point at your own file to override |
| `lua-filters` | shared filters | One per line. **Replaces** the defaults |
| `index-from` | `README` | Basename that becomes `index.html` |
| `search` | `false` | Add a Search item to the nav — set it when you also run `index-site` |
| `project` | repository name | Shown in the page title |
| `repo-url` | this repository | Link in the theme's nav |
| `pandoc-version` | `3.8.2.1` | Pinned so a Pandoc release cannot change published output |

### `build-zensical`

| Input | Default | |
| --- | --- | --- |
| `output` | `_site` | Where the site ends up |
| `site-dir` | `site` | Where Zensical writes it; change only if your config overrides the default |
| `config` | auto | `zensical.toml` or `mkdocs.yml` |
| `clean` | `true` | Clear the build cache first |
| `strict` | `false` | Abort on warnings |
| `zensical-version` | pinned | Raise deliberately; Zensical is pre-1.0 and ships every few days |
| `python-version` | `3.x` | Python used to install it |

### `build-sphinx`

| Input | Default | |
| --- | --- | --- |
| `docs-dir` | `docs` | Directory holding `conf.py` |
| `output` | `_site` | Where the site is written |
| `requirements` | — | Pip requirements file with your documentation dependencies |
| `packages` | — | Extra pip packages, one per line, if you have no requirements file |
| `python-version` | `3.12` | Pin it — Sphinx extensions drop old versions without ceremony |
| `builder` | `html` | Sphinx builder |
| `strict` | `false` | Treat warnings as errors (`-W`) |

Set `requirements` or `packages`; the action fails early if neither is given,
rather than at `sphinx-build` with a confusing error.

### `index-site`

| Input | Default | |
| --- | --- | --- |
| `site` | `_site` | The built site to index |
| `exclude-selectors` | `nav`, `header`, `footer` | CSS kept out of the index, one per line |
| `pagefind-version` | `1.5.2` | Pinned |

Skip this for generators with their own search.

### `publish-to-s3`

Authenticates with OIDC, so no long-lived AWS keys exist anywhere. The calling
job must declare `permissions: id-token: write` — a composite action cannot.

The role's trust policy has to name the **calling repository's** subject claim.
That claim is repo-specific, so a role that works for one repository will not
work for another until an entry is added.

| Input | Default | |
| --- | --- | --- |
| `role-to-assume` | — | ARN of the role to assume via OIDC |
| `aws-region` | `us-west-2` | |
| `bucket` | — | S3 bucket name |
| `prefix` | — | Key prefix within the bucket. Leave empty to publish to the bucket root |
| `sources` | `dist`, `css` | Directories to upload, one per line. `dist` uploads to the prefix root |
| `distribution-id` | — | CloudFront distribution to invalidate; omit to skip |
| `acl` | `none` | AWS recommends ACLs disabled. Set to `public-read` for a legacy bucket with no policy |
| `public-base-url` | — | Public URL serving the published objects. When set, the summary links every published file and one is fetched afterwards to confirm it is readable |
| `dry-run` | `false` | Show what would happen and change nothing |

Run it with `dry-run: true` first. It refuses to publish an empty or missing
source directory, because a build that "succeeds" into nothing would otherwise
leave the CDN serving stale objects with no signal.

Content types are set explicitly per extension rather than left to the CLI's
guess, which omits the charset and can differ between CLI versions — otherwise
what the CDN serves could change for files nobody edited.

`public-base-url` is given whole rather than built from `bucket` and `prefix`,
because neither determines it. A bucket name need not resemble the hostname in
front of it, and a CloudFront behavior or function can serve a prefix under a
different path. The only requirement is that the URL serves the same relative
structure the prefix does — `prefix: assets` published to a distribution that
maps `/static/*` to it would set `public-base-url` ending in `/static/`.

The `acl` default follows AWS's recommendation: ACLs disabled, access granted
by bucket policy. A bucket still in legacy `ObjectWriter` mode with no policy
needs `acl: public-read` — without it, objects upload successfully and are
unreadable. Setting `public-base-url` catches that: after a real publish one
file is fetched, and a 403 fails the job.

With no `prefix`, files go to the bucket root and the invalidation covers the
whole distribution — correct when the bucket belongs to one project, wrong when
it is shared. The script says so when it happens.

S3 website endpoints serve no directory listing — a URL ending in `/` returns
404 rather than an index — so the summary names each published file instead of
linking a parent directory. Set `public-base-url` to turn those into links.

It uses `aws s3 cp`, **not `sync --delete`**. Buckets often hold objects the
publishing repository does not manage, and a delete-enabled sync would remove
them with nothing to put them back. See
[ADR-0007](docs/decisions/0007-publish-without-destroying-what-you-did-not-create.md).

### `deploy-site`

| Input | Default | |
| --- | --- | --- |
| `path` | `_site` | The built site |
| `require-index` | `true` | Fail if there is no `index.html` at the root |

It refuses to publish a build with no HTML, or no index page. A generator that
"succeeds" into an empty directory would otherwise deploy a 404 over a working
site.

The deploy itself is not in this action: `actions/deploy-pages` needs a
job-level `environment:`, which a composite action cannot declare. Put it in
your own deploy job, or use a `docs-*.yml` reusable workflow.

## Adding a generator

One new action; nothing downstream changes. The contract every builder
satisfies is short, and the three existing ones are deliberately different from
each other so there is a close model to copy. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Running it on your own machine

The actions are thin wrappers around the scripts in `bin/`, which take no
GitHub context. Clone this repository once and put `bin/` on your `PATH`:

```sh
git clone https://github.com/caltechlibrary/workflows ~/cl-workflows
export PATH="$PATH:$HOME/cl-workflows/bin"
```

Then, from any project:

```sh
build-pandoc.sh --docs-dir docs      # or build-zensical.sh, build-sphinx.sh
index-site.sh --site _site           # optional
open _site/index.html
```

These are the same files CI runs, not reimplementations of them — so a local
preview cannot disagree with what gets published. They are not automatically
the same *version*: CI uses the tag your workflow pins, while your clone is
whatever you last pulled. `git -C ~/cl-workflows checkout v1` if that matters.

Every script takes `--help`.

You need [Pandoc](https://pandoc.org/) for `build-pandoc.sh`,
[Zensical](https://zensical.org/) for `build-zensical.sh`, your project's
documentation requirements for `build-sphinx.sh`, and
[Pagefind](https://pagefind.app/) for `index-site.sh`.

## Versioning

Changes are recorded in [CHANGELOG.md](CHANGELOG.md), following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Because `@v1` moves,
that file is how you find out what moved.

Reference a **major tag**:

```yaml
uses: caltechlibrary/workflows/.github/workflows/docs-pandoc.yml@v1
```

`v1` moves as fixes and backward-compatible changes ship, so you get them
without doing anything. A breaking change becomes `v2`, which you opt into
deliberately. Pin `@v1.2.3` or a commit SHA if you need to freeze.

Do not reference `@main`. It has no compatibility contract, and a change here
would reach you unannounced.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contract a build action has to
satisfy, a walkthrough of adding a generator, and the conventions this
repository keeps. The reasoning behind those conventions is recorded as
architecture decision records in [`docs/decisions/`](docs/decisions/).

`.github/workflows/ci.yml` runs on every change: `shellcheck` over the scripts,
`actionlint` over the workflows, a build per generator against its fixture, the
`deploy-site` guards, and a check that the reusable workflows have not drifted
from the current major tag.

## Known limitations

The shared Pandoc theme renders a minimal nav — Home, Search, and the
repository link. Projects wanting more override `template` with their own copy,
which reintroduces the drift this repository exists to prevent.
