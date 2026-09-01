# 2. Reference shared logic rather than copying it

- Status: accepted
- Date: 2026-08-31

## Context and Problem Statement

Caltech Library has 152 non-archived repositories and four people. Build,
publish and release logic is reinvented per repository, fixes made in one do
not reach the others, and new repositories start from whatever the last one
happened to look like.

The existing answers in the organisation both distribute logic by **copying**
it into each repository:

- `caltechlibrary/template` is a GitHub template repository carrying four
  workflows, copied into every repository created from it.
- CMTools (`cmt`) generates files into a repository from `codemeta.json`, and
  regenerates them on later runs.

Copying is measurably not holding. `codemeta2cff.yml` exists in fourteen
repositories in five distinct versions; two of them still pin
`actions/checkout@v2`. `build-sphinx.yml` in `dibs` and `foliage` has the same
origin and the same author and has diverged: dibs on Python 3.8 (end of life
October 2024) and the removed `::set-output`, foliage on 3.11 and
`$GITHUB_OUTPUT`.

The instructive part is what did *not* drift. Every one of those fourteen
copies references `caltechlibrary/codemeta2cff`, and that reference is
consistent everywhere, for free. The copied wrapper around it is what fell
apart.

## Decision Drivers

- Fixes must reach repositories without anyone editing 152 files.
- Nothing may be written into a consumer's working tree without them asking.
- A repository must be able to opt out without that being a defection.
- Four people cannot maintain a mechanism that needs per-repository upkeep.

## Considered Options

1. Keep copying, and add tooling that detects and repairs drift
2. Generate workflows from a central definition, CMTools-style
3. Reference shared logic from a versioned repository

## Decision Outcome

**Chosen: option 3.** Consumers reference workflows and actions in this
repository; nothing is copied into them.

### Option 1: copy plus drift detection -- rejected

This is the shape the organisation already has, plus a repair mechanism. It
keeps the failure mode and adds machinery to paper over it: the copies still
diverge, and something has to reconcile 152 of them continuously. It also
requires an authority that edits other people's repositories, which is the
behaviour people object to in the tools that already do it.

### Option 2: generate workflows centrally -- rejected

A generated file is a copy that a tool keeps overwriting. It combines the worst
properties of both mechanisms: consumers get surprise overwrites of files they
edited, *and* they still do not get fixes unless someone re-runs the generator.
CMTools demonstrates this directly -- CL-web-components shipped `0.0.12` in
`src/version.js` across four releases and seven months because nothing
regenerated it.

It also requires every consumer to install and run the generator locally, which
is a real barrier for anyone whose workflow is not built around that toolchain.

### Option 3: reference -- chosen

The source owns the logic, the consumer names a version, and improvements
arrive on the consumer's next run without anything being written to their
working tree.

## Consequences

Good:

- A fix here reaches every consumer on its next run.
- Consumers can pin or freeze; nothing arrives unannounced (see ADR-0006).
- Leaving is cheap: a repository can stop referencing a workflow and assemble
  the actions itself, or write its own job entirely.

Bad, and accepted:

- **This repository becomes a single point of failure.** A bad release reaches
  every consumer at once. Mitigated by CI that tests every generator against a
  fixture on every change -- a shared repository nothing tests is worse than a
  copy.
- **Debugging gains an indirection.** A failure is now one repository away from
  the logs being read.
- **Drift relocates rather than disappearing.** Repositories pinned to
  different majors are still inconsistent -- but visibly and auditably so.
- **Someone has to own this repository.** That is an ongoing commitment, not a
  one-time cleanup.

## More Information

- `README.md` -- how to reference the workflows and actions
- ADR-0006 -- how versions propagate
- `caltechlibrary/codemeta2cff` -- an existing action in the organisation,
  referenced consistently everywhere, whose copied wrapper drifted
