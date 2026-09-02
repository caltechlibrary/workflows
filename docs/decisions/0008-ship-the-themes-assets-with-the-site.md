# 8. Ship the theme's assets with the site; projects add rather than replace

- Status: accepted
- Date: 2026-09-02

## Context and Problem Statement

The shared Pandoc template fetched its own assets by absolute URL from another
project's CDN:

```html
<link rel="stylesheet" href="https://caltechlibrary.github.io/css/site.css">
<link rel="stylesheet" href="https://media.library.caltech.edu/cl-webcomponents/css/code-blocks.css">
<script type="module" src="https://media.library.caltech.edu/cl-webcomponents/copyToClipboard.js"></script>
```

So every site built with this action depended on `CL-web-components` publishing
to S3 and on `caltechlibrary.github.io` acting as an asset host. Neither
arrangement was agreed to by anyone, and nothing tested either. The S3 copies
were thirteen months out of date when this was found: they reported version
`0.0.12` while the project itself was at `0.0.16`.

The files are not what their location suggested. `code-blocks.css` styles
`pre` and the copy button on documentation pages; `copyToClipboard.js` creates
that button and is not a web component at all — no `customElements.define`,
and not exported from its project's `mod.js`. `site.css` styles `:root`, `body`,
`header`, `nav`, `section` and `aside`: exactly the structure this template
emits. All three are this theme's, and the projects holding them were consumers
rather than owners.

That leaves a second question. Once the theme owns its assets, how does a
project change how its own site looks?

## Decision

**The theme's assets live here, in `pandoc/css` and `pandoc/js`, and
`build-pandoc` copies them into every site it builds.** A published site serves
them itself and fetches nothing.

**Projects add; they do not replace.** `--extra-css` and `--extra-js` ship a
project's own files and load them *after* the theme's. For CSS that is
sufficient to override anything, because later rules win.

`--site-base` prefixes both, defaulting to `/<repo>/` where GitHub Pages puts a
project site. The default is set by the action, not the script, so the script
keeps knowing nothing about CI.

## Considered Options

1. Keep fetching assets from another project's CDN
2. Publish the theme's assets to S3 from this repository
3. Ship them with each site, and let projects overlay files by name
4. Ship them with each site, and let projects add files that load afterwards

## Decision Outcome

**Chosen: option 4.**

### Option 1: keep the CDN references — rejected

It makes every documentation site in the organization depend on one project's
bucket and on a content repository nobody designated as an asset host. The
staleness that prompted this was the predictable result.

### Option 2: publish the assets to S3 from here — rejected for now

Coherent, and right for assets that sites outside this build system embed —
`footer-global.js` is exactly that, and keeps its CDN URL. But for files only
this theme's own pages use, it buys a publishing pipeline, a role and a
versioning convention to solve a problem that copying already solves.

### Option 3: overlay by filename — rejected

To change one rule, a project copies the whole theme file into its repository
and edits it. That copy is committed, edited by a human, and silently falls
behind when the theme improves. It is the failure this repository exists to
avoid, reproduced one directory down.

### Option 4: additive — chosen

A project's file contains only what is genuinely the project's. Nothing
duplicates the baseline, so nothing can drift from it. The cascade does the
overriding, which is what a cascade is for.

## Consequences

Good:

- A site serves its own styling and depends on nothing at render time.
- Fixing the theme is one change here plus a move of `v1`, and reaches every
  adopting repository.
- No project needs a copy of a theme file, so no project can hold a stale one.

Bad, and accepted:

- Each built site carries its own copy of the assets. These are build output,
  not committed files — regenerated every run, editable by nobody — so they
  are duplication in the same sense `dist/` is, which is to say not the kind
  that rots.
- Assets are copied even when a project overrides the template and references
  none of them. The result is an unused file on that site. Detecting this would
  mean parsing the template for references, which is worse than the waste.
- Overriding by filename still works, because the copy is unconditional. It is
  documented as a fork rather than prevented.
- The `--template` escape hatch remains, and a project taking it opts out of
  future changes to the shared template. That is the cost of total control, and
  it is confined to one file.

## More Information

- The assets came from `CL-web-components` and `caltechlibrary.github.io`. Both
  keep their copies until they adopt this build; those copies are leftovers, and
  this repository is canonical.
- caltechlibrary/caltechlibrary.github.io#6 — the organization site consuming
  the theme it currently hosts. It is served at a domain root, so it will be the
  first user of `site-base: /`.
- caltechlibrary/CL-web-components#51 — retiring that project's forked
  template.
- [ADR-0002](0002-reference-shared-logic-rather-than-copying-it.md) — the same
  argument applied to logic rather than assets.
