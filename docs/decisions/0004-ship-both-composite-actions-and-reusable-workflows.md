# 4. Ship both composite actions and reusable workflows

- Status: accepted
- Date: 2026-08-31

## Context and Problem Statement

GitHub offers two ways to share CI logic, and they are not interchangeable:

- A **composite action** is a bundle of steps, used inside a job the caller
  writes.
- A **reusable workflow** is a whole job, used instead of a job the caller
  writes.

This repository ships both for the same work: `build-pandoc` (action) and
`docs-pandoc.yml` (workflow, which calls it). That looks like duplication, and
the tempting simplification is to keep only the workflow -- a consumer writes
ten lines instead of thirty, which is the headline benefit.

## Decision Drivers

- The easy path should be genuinely easy: one `uses:` and some inputs.
- A project with an unusual build must not be forced to abandon the shared
  logic entirely.

## Considered Options

1. Reusable workflows only
2. Composite actions only
3. Both

## Decision Outcome

**Chosen: option 3.** The actions are the substance; the reusable workflows are
a convenience wrapper over the common assembly.

### Option 1: reusable workflows only -- rejected

**A caller cannot add steps to a job it did not write.** This is not a
stylistic limitation; it makes reusable workflows unusable for any project that
must prepare something before its docs build.

CL-web-components is the concrete case. Its site publishes compiled component
bundles, so `deno task build` has to run before rendering, which needs
`denoland/setup-deno` first. There is nowhere in a reusable workflow to put
that step. Under this option the project's only recourse would be abandoning
the shared logic and going back to a hand-written 127-line workflow.

A `pre-build:` string input was tried as a workaround. It handles a shell
command but not an action -- installing a toolchain properly means
`uses: denoland/setup-deno@v2`, and `uses:` cannot be supplied as an input.

### Option 2: composite actions only -- rejected

Every consumer would hand-write the Pages plumbing: the deploy job, the
`environment:` block, `permissions`, concurrency, the `if:` that stops pull
requests from deploying. That is exactly the boilerplate that drifts, and
getting the pull-request condition wrong means deploying from unreviewed
branches.

### Option 3: both -- chosen

Most repositories reference `docs-<engine>.yml` and write about ten lines.
Repositories that need control over the surrounding steps use the actions in
their own job and keep everything they are not changing.

## Consequences

Good:

- Needing something unusual costs a level of indirection, not the shared logic.
  CL-web-components' caller is 68 lines instead of 127, and the Pandoc
  invocation, both Lua filters, the theme and the search index are still
  shared.
- The two tiers document the escape hatch. A project that outgrows the workflow
  has an obvious next step rather than a fork.

Bad, and accepted:

- Two things to keep in step. A new input on an action usually wants plumbing
  through the matching workflow.
- **`uses:` cannot take an expression**, so the reusable workflows reference
  this repository's own actions at a literal ref, which must be updated when a
  version is released. `ci.yml` fails if those refs drift from the current
  major tag.
- Consumers must understand which tier they want. `CONTRIBUTING.md` and
  `README.md` both state the rule: need to control the steps around it, use the
  action; want the whole job handled, use the workflow.

## More Information

- `README.md` -- "Building the pipeline yourself"
- ADR-0003 -- why there is one build action per generator
