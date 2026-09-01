# 3. One build action per documentation generator

- Status: accepted
- Date: 2026-08-31

## Context and Problem Statement

The team is not going to converge on one documentation generator. Robert has
reason to stay on Pandoc, other projects want Zensical, and `dibs` and
`foliage` are on Sphinx. Whatever this repository supports has to accommodate
all three, and whatever comes next.

Three actions that each install a toolchain and run a build look redundant.
`build-pandoc`, `build-zensical` and `build-sphinx` share a shape, and the
obvious simplification is one `build-docs` action with an `engine:` input.

## Decision Drivers

- Adding a generator should not require touching the existing ones.
- A consumer should see only the options relevant to the generator they use.
- The inputs are a public API once consumers reference `@v1` (ADR-0006).

## Considered Options

1. One `build-docs` action with an `engine:` input
2. One action per generator

## Decision Outcome

**Chosen: option 2**, one `build-*` action per generator, sharing a contract
rather than an implementation.

### Option 1: one action with an `engine:` input -- rejected

The generators do not take comparable inputs:

| Generator | Needs |
| --- | --- |
| Pandoc | `template`, `lua-filters`, `index-from`, `extra-sources`, `include` |
| Zensical | `config`, `site-dir`, `clean`, `zensical-version` |
| Sphinx | `requirements`, `packages`, `python-version`, `builder`, `strict` |

A single action would be the union of all of these -- currently 25 inputs, of
which any given consumer would use about seven. Every generator added
afterwards makes the action worse for everyone already using it, and every
input has to document which engines it applies to and be ignored by the rest.

This is the failure mode this repository is otherwise careful about: growing a
flag per special case until the shared thing serves nobody well.

### Option 2: one action per generator -- chosen

Each action carries only its own inputs. Adding a generator is one new
directory; nothing existing changes.

What is shared is a **contract**, not code. Every build action must write a
directory of static HTML to `output` with `index.html` at its root. Everything
downstream -- `index-site`, `deploy-site`, the Pages upload, the deploy --
depends on that and nothing else, which is what makes changing generator a
one-action decision rather than a rewrite.

## Consequences

Good:

- The three existing actions serve as models, and they are deliberately
  different from each other: Pandoc runs a binary over a source directory,
  Zensical installs from PyPI and reads its own config, Sphinx needs the
  project's own pinned dependencies. A fourth generator has a close one to
  copy.
- Generator-specific behaviour stays where it belongs. Sphinx leaves
  `.doctrees` in its output and Zensical writes to `site/`; both are handled in
  their own action rather than in shared branching.

Bad, and accepted:

- Some duplication between the actions -- argument marshalling, output
  validation. Judged cheaper than a union of inputs, and each copy is small.
- Nothing enforces the contract at the type level. It is enforced by
  `deploy-site` refusing to publish a build with no HTML or no index page, and
  by each generator having a CI job asserting on its output.

## More Information

- `CONTRIBUTING.md` -- the contract, and a walkthrough of adding a generator
- ADR-0004 -- why there are also reusable workflows wrapping these actions
