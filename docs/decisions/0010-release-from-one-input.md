# 10. Release from one input, as a commit of its own

- Status: accepted
- Date: 2026-11-20

## Context and Problem Statement

A release in the org’s repositories means writing the same version into
several files by hand: `pyproject.toml`, `uv.lock` or `__version__`,
`codemeta.json`, `CITATION.cff`, and a new section in `CHANGELOG.md` with its
compare links. Then a tag, which some repositories push by hand and some
leave to a workflow that tags whenever `pyproject.toml`’s version changes on
`main`.

Each repository does this a little differently, and the files drift: a
`codemeta.json` that nobody remembers to update can stay several releases
behind the tags.
`build-python-dist` catches disagreeing versions in a Python package, but only
at build time, after the release commit exists.

Boffo already had the answer for one repository: a workflow run by hand with
a version that updates the files, commits them, and opens a draft release.
The question is whether that becomes the shared way, and in what shape.

## Decision Drivers

- Naming a release once: a version or a bump level, in one place.
- Every file that records a version agrees after a release, and nothing is
  released while they disagree.
- Repositories that want only a tag aren’t made to publish GitHub releases.
- A release can be previewed, locally and in CI, before anything is pushed.

## Considered Options

1. Bump the version in the same commit as the changes it releases
2. Derive the version from git tags at build time (`setuptools-scm`, `hatch-vcs`)
3. A release commit made by tooling from one input

## Decision Outcome

**Chosen: option 3.** `release.yml`, run by hand with `major`, `minor`,
`patch`, or a version, calls `bin/prepare-release.sh` through the
`prepare-release` action, then commits “Release X.Y.Z”, tags `vX.Y.Z`, and
pushes the commit and tag atomically. With `draft-release` it opens a draft
GitHub release instead, as Boffo does.

The script edits the working tree and nothing else, takes no GitHub context,
and runs on macOS’s bash 3.2 (ADR-0005), so `prepare-release.sh minor`
followed by `git diff` previews a release on a laptop.

### Option 1: bump with the changes -- rejected

One step fewer, and every state of `main` has its own version. But the
version is chosen before knowing what else ships with it; two branches that
both bump it conflict in every versioned file; reverting a change reverts the
version with it; and a reviewer judges the version along with the code. It
also does nothing about the files drifting, which is the actual problem.

### Option 2: versions from tags -- rejected

Only the tag would ever be created by hand. But `codemeta.json`, `CITATION.cff`,
and the changelog still carry the version and date, so they would still need
the edits this decision exists to automate; and `build-python-dist` needs a
literal version to check before building.

### Option 3: a release commit from one input -- chosen

- **The current version comes from the files, which must agree.** A
  repository whose files already disagree is told which ones, rather than
  released with the disagreement baked in.
- **The new version must be greater than the current one and than every
  `vX.Y.Z` tag**, so a stale file can’t produce a version that already
  shipped.
- **`[Unreleased]` must have entries.** A release with nothing to say is
  refused, which keeps the changelog from falling behind the tags.
- **Nothing is written unless every check passes.** Edits are made to copies
  and checked before any replaces the real file.
- **`uv.lock` is edited directly**, not regenerated with `uv lock`. Only the
  project’s own `[[package]]` version changes, so the edit needs neither `uv`
  nor the network, and `uv lock --check` accepts the result.
- **Dates are Pasadena dates.** Runners use UTC, which is already tomorrow
  on a Pasadena afternoon.

## Consequences

Releasing needs one input and one click, and the changelog has to be kept
under `[Unreleased]` as work lands.

A tag pushed with the workflow’s own `GITHUB_TOKEN` starts no other
workflows. A repository that builds or publishes on a new tag uses
`draft-release`, since publishing the draft is a person’s action, or passes a
GitHub App token as `token`.

A repository that consumers reference by a moving major tag (ADR-0006), as
they do this one, sets `major-tag`, and the same push moves that tag to the
release. It can’t be combined with `draft-release`: the draft’s tag doesn’t
exist until the draft is published, so the major tag would point at a release
that might never be made. This repository releases itself with
`self-release.yml`, which calls `release.yml` from the branch it runs on.

A repository that protects its default branch has to let the workflow push
to it, or pass a `token` that can.

Repositories with a tag-on-version-change workflow can drop it once they call
`release.yml`. Left in place, it either doesn’t run, since a push by the
workflow’s own token starts no workflows, or finds the tag already there and
skips.

Files the script doesn’t know, such as `package.json` or a `VERSION` file,
aren’t updated. Adding one means teaching the script to read, write, and
check it, and adding it to the fixture.
