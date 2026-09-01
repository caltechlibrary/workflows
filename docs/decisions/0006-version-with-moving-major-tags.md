# 6. Version with moving major tags, and do not accept `@main`

- Status: accepted
- Date: 2026-08-31

## Context and Problem Statement

Referencing shared logic (ADR-0002) only works if consumers know what they are
referencing. The ref in a `uses:` line is the entire contract between this
repository and the 152 that might depend on it.

Existing practice in and around the organisation does not provide one:

- All fourteen copies of `codemeta2cff.yml` reference
  `caltechlibrary/codemeta2cff@main`.
- `inveniosoftware/workflows`, the model for this repository, tells consumers
  to use `@master` and has no tags at all.

Under both, a breaking change lands in every consumer with no warning and no
way to decline it. That is the property that makes people reluctant to depend
on shared tooling, and it is worse than copying, because at least a copy holds
still.

## Decision Drivers

- Fixes should propagate without anyone editing consumer repositories.
- Breaking changes must be opt-in, per repository.
- A repository must be able to freeze completely if it needs to.
- The mechanism should be one the team already trusts.

## Considered Options

1. `@main`, as the organisation and the model repository both do
2. Exact version tags only
3. Moving major tags

## Decision Outcome

**Chosen: option 3.** Consumers reference `@v1`, which moves as
backward-compatible changes ship. A breaking change becomes `@v2`.

### Option 1: `@main` -- rejected

No contract. Every change is a potential outage across every consumer
simultaneously, and consumers have no way to say "not yet". This is the current
practice being replaced, not an option retained for compatibility.

### Option 2: exact tags only -- rejected

Safe, but fixes stop propagating: every consumer must be edited for every
patch, across 152 repositories with four people. That reintroduces the
maintenance burden that motivated ADR-0002.

### Option 3: moving major tags -- chosen

This is the mechanism the team already relies on without thinking about it.
`actions/checkout@v7` and `aws-actions/configure-aws-credentials@v6` are
moving major tags; nobody pins those to a SHA, and nobody is surprised by them.

- Fixes flow automatically within a major.
- Breaking changes require a deliberate edit.
- `@v1.2.3` or a commit SHA remains available for a repository that must
  freeze.

## Consequences

Good:

- Improvements reach consumers with no action, and breakage does not.
- Adoption is easier to argue for, because the failure mode people fear --
  something changes under us -- is the one thing the contract forbids.

Bad, and accepted:

- **The inputs become a public API.** Once repositories reference `@v1`,
  renaming an input is a breaking change for all of them. The input surface has
  to stay small and boring, while the implementation behind it can change
  freely.
- **Releasing has a manual step that can be got wrong.** `uses:` cannot take an
  expression, so the reusable workflows reference this repository's own actions
  at a literal ref. Releasing `v2` without updating those strings would ship a
  new workflow driving old actions. `ci.yml` fails when they do not all match
  the current major tag -- a guard added because this is exactly the sort of
  thing that is discovered in production.
- Consumers pinned to different majors are inconsistent with each other. That
  is visible and auditable, unlike copies that merely look similar.

## More Information

- `README.md` -- "Versioning"
- `.github/workflows/ci.yml` -- the self-reference check
- ADR-0002 -- why referencing rather than copying
