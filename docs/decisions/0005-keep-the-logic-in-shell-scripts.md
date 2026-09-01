# 5. Keep the logic in shell scripts, with actions as thin wrappers

- Status: accepted
- Date: 2026-08-31

## Context and Problem Statement

Every action here installs a toolchain, marshals its inputs into arguments, and
calls a script in `bin/`. The scripts could just as well be `run:` blocks
inside `action.yml`, which would remove a directory, a layer of argument
passing, and the need to keep the two in step.

The reason not to is a requirement that is easy to lose sight of: **people have
to be able to build the site on their own machine.** Moving documentation
publishing into CI is only acceptable if it does not take local preview away,
and a local preview is only trustworthy if it cannot disagree with what gets
published.

## Decision Drivers

- A local build must produce what CI publishes, not an approximation.
- Contributors should not need a GitHub context, a runner, or `act`.
- Not everyone on the team works the same way; the mechanism should not assume
  a particular local toolchain beyond the generator itself.

## Considered Options

1. Logic in `run:` blocks inside `action.yml`
2. Logic in the consuming repository, called by the action
3. Logic in shell scripts here, called by the action

## Decision Outcome

**Chosen: option 3.** `bin/*.sh` holds the logic and takes no GitHub context;
`action.yml` installs tools and translates inputs into flags.

### Option 1: logic in `action.yml` -- rejected

Fewer files, but the logic becomes unrunnable outside a workflow. Reproducing a
CI build locally would mean copying commands out of YAML by hand, which is a
reimplementation -- and reimplementations drift, which is the failure this
repository exists to prevent.

### Option 2: logic in the consuming repository -- rejected

This is the model `inveniosoftware/workflows` uses: its reusable workflow calls
`./run-tests.sh` from the repository being tested. It gives each project full
control, but it puts the logic back in 152 places, which is the copying
problem in ADR-0002.

### Option 3: scripts here -- chosen

```
bin/build-pandoc.sh          the logic; no GitHub context
.github/actions/build-pandoc install a toolchain, marshal arguments, call it
```

A contributor clones this repository once, puts `bin/` on `PATH`, and runs the
same file CI runs.

## Consequences

Good:

- A local preview is the same code path as the published site, not a parallel
  implementation that can drift from it.
- The scripts are testable directly, and take `--help`.
- `shellcheck` covers the substance. Logic buried in YAML `run:` blocks is only
  reachable by `actionlint` delegating to shellcheck, which is weaker.

Bad, and accepted:

- **Same file does not mean same version.** CI runs the tag the consumer pinned;
  a local clone is whatever was last pulled. Documented, with the remedy
  (`git checkout v1`), because the alternative is a claim of equivalence that
  is not quite true.
- Argument marshalling is real code in `action.yml` and has its own failure
  modes -- multi-line inputs need explicit splitting, and the path to the script
  goes through `github.action_path`. Both are called out in `CONTRIBUTING.md`.
- Contributors need the generator installed locally to run a script. That is
  unavoidable for any local build and is not specific to this arrangement.

## More Information

- `README.md` -- "Running it on your own machine"
- `CONTRIBUTING.md` -- the marshalling traps
