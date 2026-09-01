# Contributing

## Adding a documentation generator

The three existing builders — Pandoc, Zensical, Sphinx — are deliberately
different from each other, and they exist as much to be copied from as to be
used. If you want a generator that is not here, you are adding one action and
changing nothing else.

Pick the closest existing one and work from it:

| If your generator… | start from |
| --- | --- |
| runs a binary over a source directory | `build-pandoc` |
| installs from PyPI and reads its own config file | `build-zensical` |
| needs the project's own pinned dependencies | `build-sphinx` |

### The contract

A `build-*` action has to satisfy five things. Everything downstream —
`index-site`, `deploy-site`, the Pages upload, the deploy — depends on these
and nothing else.

1. **Write a directory of static HTML to `output`.** Default it to `_site`.
   Generators that insist on their own location (Sphinx wants
   `docs/_build/html`, Zensical wants `site/`) relocate afterwards. This is the
   whole seam: downstream never learns which generator ran.

2. **Put `index.html` at the root of it.** `deploy-site` refuses to publish
   without one, because a site that "builds" into a directory with no index
   deploys a 404 over a working site.

3. **Do not write build state into the source tree.** Build straight into
   `output` where the generator allows it. Sphinx leaves a `.doctrees`
   directory in its output; `build-sphinx.sh` removes it. Generated files
   landing in the source tree is how they end up committed.

4. **Keep the logic in `bin/`, not in `action.yml`.** The action installs a
   toolchain and marshals arguments. The script does the work, takes no GitHub
   context, and runs on a laptop. This is what makes a local preview provably
   the same as what CI publishes.
   ([ADR-0005](docs/decisions/0005-keep-the-logic-in-shell-scripts.md))

5. **Pin the toolchain version, and say why in the input description.** Every
   builder here pins. An unpinned install means a generator release you did not
   choose changes your published output.

### The five files

```
bin/build-<engine>.sh                        the logic
.github/actions/build-<engine>/action.yml    install + marshal
test/fixture-<engine>/                       a minimal project
.github/workflows/ci.yml                     a job exercising the action
README.md                                    an entry and an input table
```

A `docs-<engine>.yml` reusable workflow is optional. Add one only if the
build/index/deploy sequence for that generator is worth wrapping; projects that
need setup steps first cannot use it anyway (see below).

### Walking through it

**1. Write the script.** Copy the closest `bin/build-*.sh`. Keep the flag
parsing shape, keep `--help`, and end by counting the HTML it produced and
failing if that count is zero. Silent success on an empty build is the failure
mode that matters.

**2. Write the action.** Copy the matching `action.yml`. Three things are easy
to get wrong:

- Reach the script with
  `"${{ github.action_path }}/../../../bin/build-<engine>.sh"`. GitHub checks
  out the whole repository for a remote action, so `bin/` is there.
- Multi-line inputs arrive as one string. Split them the way the existing
  actions do:

  ```bash
  while IFS= read -r line; do
    [ -n "$line" ] && ARGS+=(--thing "$line")
  done <<< "$INPUT"
  ```

- Pass inputs through `env:` rather than interpolating `${{ }}` straight into
  `run:`. And remember backticks inside double quotes are command substitution
  in bash — `echo "set \`foo\`"` tries to run `foo`.

**3. Add a fixture.** `test/fixture-<engine>/` with the smallest project that
still exercises something real: two pages, a link between them, and a table if
the generator does anything interesting with one.

**4. Add a CI job.** Exercise it **through the action**, not by calling the
script, so the argument marshalling is covered too. Then assert on the output —
that `index.html` exists, that the second page rendered, that no build state
leaked. Assertions that would have caught a real bug are worth more than a
count of pages.

**5. Document it.** An entry in the README's action table, an input table, and
anything surprising about the generator. Both existing entries carry a
surprise worth knowing: Zensical writes directory-style URLs
(`second/index.html`, not `second.html`), and Sphinx dependencies belong to the
project rather than to this repository.

### Things that will bite you

- **Do not add an `engine:` input to an existing action.** The inputs genuinely
  differ per generator — Pandoc needs a template and Lua filters, Sphinx needs
  requirements and a Python version, Zensical needs its own config. One action
  would become a union of mostly irrelevant options, and every new generator
  would make it worse for everyone already using it.
  ([ADR-0003](docs/decisions/0003-one-build-action-per-generator.md))

- **A reusable workflow gives the caller nowhere to add steps.** If a project
  has to compile something before its docs build, it cannot use
  `docs-<engine>.yml` — it has to assemble the actions in its own job.
  CL-web-components is the example: it runs `deno task build` first, so it uses
  `build-pandoc` directly. That is the design working, not a workaround.
  ([ADR-0004](docs/decisions/0004-ship-both-composite-actions-and-reusable-workflows.md))

- **`uses:` cannot take an expression.** Reusable workflows reference this
  repository's own actions at a literal ref, so releasing means updating those
  strings. CI fails if they drift from the current major tag — see the
  self-reference check in `ci.yml`.

## Conventions

- **Keep the input surface small.** Once repositories reference `@v1`, renaming
  an input is a breaking change for all of them. The inputs are the real API;
  the implementation behind them can change freely.
  ([ADR-0006](docs/decisions/0006-version-with-moving-major-tags.md))

- **Make assumptions explicit.** If an action needs `docs/` to exist, that
  should be an input with a default, not an unstated requirement.

- **Say what was dropped.** If a build skips or truncates something, log it.
  Silent truncation reads as "covered everything" when it did not.

- **Leaving is allowed.** A project that needs behaviour which does not
  generalise should write its own job and use whichever actions still fit —
  or none. That is better than growing a flag for every special case until the
  shared thing serves nobody well. If dropping the shared workflow feels like
  defection, people will lobby for flags instead, and the flags will win.

## Testing

`.github/workflows/ci.yml` runs on every change:

- `shellcheck --severity=style` over `bin/*.sh`
- `actionlint` over the workflows
- a build per generator against its fixture, plus assertions on the output
- the `deploy-site` guards
- the self-reference check

Run the scripts directly while developing — they need no GitHub context:

```sh
bin/build-pandoc.sh --docs-dir test/fixture/docs --output /tmp/site
bin/index-site.sh --site /tmp/site
```

## Decisions

Why this repository is shaped the way it is lives in
[`docs/decisions/`](docs/decisions/), as
[MADR](https://adr.github.io/madr/) architecture decision records. Read those
before changing the contract, the versioning scheme, or the split between
actions and workflows — each records alternatives that were costed and
rejected, which is the part the code cannot tell you.

Adding a generator does not need an ADR. Changing the contract every generator
satisfies does.
