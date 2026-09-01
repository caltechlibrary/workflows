# 1. Record architecture decisions

- Status: accepted
- Date: 2026-08-31

## Context and Problem Statement

This repository exists to be depended on. Once other repositories reference
`@v1`, its structure is an API, and several of its choices look like
unnecessary complication to anyone who did not watch them being made: three
build actions that could apparently be one, a script layer that could
apparently be inlined into `action.yml`, a reusable workflow that duplicates
what the actions already do.

Each of those is the survivor of an alternative that was tried or costed and
rejected. Nothing in the code records that. The next person to read it -- human
or LLM -- sees only the surviving design and is free to "simplify" it back into
the thing that already didn't work.

## Decision

Record architecturally significant decisions as ADRs in `docs/decisions/`,
following [MADR](https://adr.github.io/madr/), matching the conventions used in
Alchemist so the practice is the same across Caltech Library repositories. The
format originates with Michael Nygard's [Documenting Architecture
Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

Conventions:

- One file per decision, `NNNN-title-in-kebab-case.md`, numbered sequentially
  in the order recorded (not the order decided).
- Each has a status: `proposed`, `accepted`, `rejected`, `deprecated`, or
  `superseded by ADR-NNNN`.
- **ADRs are immutable once accepted.** A decision that changes is not edited;
  a new ADR supersedes it, and the old one is marked as superseded.
- Corrections of *fact* about what shipped are fine to amend in place, dated
  and noted. Changes of *decision* get a new ADR.
- Record the rejected options and why. That is usually the most valuable part
  and the part that cannot be recovered from the code.

## Consequences

The decisions that shape this repository's public surface become linkable, so
`CONTRIBUTING.md` can state a rule and point at the reasoning instead of
carrying it.

Adding a generator does not need an ADR. Changing the contract every generator
satisfies does.

The cost is discipline: an ADR nobody writes is worthless, and one nobody
supersedes when the decision changes is worse than worthless. The likeliest
failure here is that a rule gets relaxed in practice -- a flag added to a
shared action, a project pinned to `@main` -- without the ADR that forbade it
being superseded.
