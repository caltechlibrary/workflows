# 9. Keep PyPI publishing in the calling repository

- Status: accepted
- Date: 2026-11-02

## Context and Problem Statement

Many of the org’s repositories are Python packages on PyPI, and each needs the
same release workflow: check that the version numbers agree, build the sdist
and wheel, check them, and upload them. Everything else in this repository is
shared, so the obvious move is to share the whole thing — one reusable
`python-publish.yml` that a repository calls with a single `uses:`.

The upload cannot be shared, for reasons outside this repository’s control:

- `pypa/gh-action-pypi-publish` is unsupported from inside a composite
  action. Its README says so, and adds that building and publishing in the
  same job is the insecure arrangement it wants to discourage: the job
  holding `id-token: write` should run nothing but the upload.
- PyPI Trusted Publishing does not work when the upload runs in a reusable
  workflow. The action’s README says that too, and recommends keeping the
  publish job in a top-level workflow.
- Trusted Publishing is the only credential worth using. The alternative is a
  long-lived API token stored as a secret in every repository, which is the
  thing Trusted Publishing exists to remove.

## Decision Drivers

- No long-lived PyPI credentials anywhere.
- The checks that catch a bad release — disagreeing versions, a tag that does
  not match, an empty or malformed `dist/` — should be written once.
- A consumer should not be able to wire the pieces together in a way that
  publishes something unchecked.

## Considered Options

1. A reusable workflow that builds and publishes, authenticating with an API
   token
2. A reusable workflow that builds and publishes with Trusted Publishing
3. A shared build action; the publish job stays in each repository

## Decision Outcome

**Chosen: option 3.** `build-python-dist` checks, builds, and uploads `dist/`
as an artifact. The repository’s own `publish.yml` has a build job that uses
it and a publish job that downloads the artifact and runs
`pypa/gh-action-pypi-publish`.

### Option 1: API token -- rejected

It works from a reusable workflow, and it puts a credential that can publish
to the package into every repository’s secrets, where it outlives whoever
created it. Rotating or revoking it is per-repository manual work.

### Option 2: Trusted Publishing from a reusable workflow -- rejected

Unsupported. Building on it would mean a workflow that fails at the upload,
the one step that cannot be rehearsed without publishing. Revisit this if PyPI
adds support; the pypa README tracks it.

### Option 3: shared build, local publish -- chosen

The publish job is about fifteen lines, and nearly all of it is the
`environment:` block and `permissions: id-token: write` that Trusted
Publishing needs anyway. Those belong to the repository regardless: the
trusted publisher registered on PyPI names the repository, the workflow file,
and the environment, and any protection rules on that environment are set in
the repository’s own settings.

## Consequences

Good:

- No PyPI credential is stored anywhere.
- The build runs in a job with read-only permissions. Only the publish job can
  mint an OIDC token, and it runs nothing but the upload.
- The version and `dist/` checks are shared and tested here. They are the part
  that varies least between packages and fails most quietly when copied.
- The publish step a repository owns is the one that has to name it anyway.

Bad, and accepted:

- Every package repository carries a short publish job, and those can drift
  from one another. The README holds the example to copy.
- The build job’s artifact name and the publish job’s download must match.
  Both default to `dist`, so the coupling is invisible until someone renames
  one. The README says so.

## More Information

- `README.md` -- “Python packages”
- [pypa/gh-action-pypi-publish](https://github.com/pypa/gh-action-pypi-publish)
  -- the limitations quoted above
- ADR-0004 -- composite actions and reusable workflows
