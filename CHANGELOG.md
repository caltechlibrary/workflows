# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Consuming repositories reference a **moving major tag** such as `@v1`, which
advances with every backward-compatible change. This file is how you find out
what moved. See
[ADR-0006](docs/decisions/0006-version-with-moving-major-tags.md).

## [Unreleased]

## [1.2.0] - 2026-09-02

### Added

- The Pandoc theme's own CSS and JS now live here, in `pandoc/css` and
  `pandoc/js`, and are copied into every site `build-pandoc` builds. A
  published site serves them itself instead of fetching them from another
  project's CDN. See
  [ADR-0008](docs/decisions/0008-ship-the-themes-assets-with-the-site.md).
- `build-pandoc` inputs `extra-css` and `extra-js`: files a project ships with
  its site and loads *after* the theme's. For CSS that is enough to restyle
  anything the theme does, because later rules win, so no project needs a copy
  of a theme file.
- `build-pandoc` input `site-base`, the URL prefix those assets are served
  under. Defaults to `/<repo>/`; set it to `/` for a site at a domain root.

### Changed

- The shared template no longer fetches `site.css`, `code-blocks.css` or
  `copyToClipboard.js` by absolute URL. Those had made every documentation site
  depend on `CL-web-components` publishing to S3 and on
  `caltechlibrary.github.io` acting as an asset host; the S3 copies were
  thirteen months stale. `footer-global.js` and the Caltech Library logo keep
  their CDN URLs, because sites outside this build system embed them.
- **If you use the shared template and your site is served at a domain root,
  set `site-base: /`.** The default is `/<repo>/`, which is correct for a
  GitHub Pages project site. Left wrong, the theme's stylesheets 404 and the
  site loses its styling.
- Documented which repeated values in examples must match and which are
  coincidental: a build action's `output` and `deploy-site`'s `path` must be
  the same directory, while `prefix` and the path in `public-base-url` need
  not correspond.
- Documented that `public-base-url` is independent of `bucket` and `prefix`.
  A bucket name need not resemble the hostname in front of it, and a
  CloudFront behavior can serve a prefix under a different path; the only
  requirement is that the URL serves the same relative structure.

## [1.1.0] - 2026-09-01

### Added

- `publish-to-s3` action: uploads built assets to S3 and invalidates the
  matching CloudFront paths, authenticating with OIDC so no long-lived AWS
  keys are required. Replaces per-repository `publish_to_s3.bash` and
  `invalidate_cdn.bash` scripts.
- `public-base-url` input on `publish-to-s3`. The job summary links every
  published file, and after a real publish one of them is fetched to confirm
  it is readable — an object uploaded without an ACL its bucket requires
  otherwise succeeds and is silently unreadable. S3 website endpoints serve no
  directory listing, so the files have to be named individually.
- `CHANGELOG.md`, following
  [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and a release
  procedure in `CONTRIBUTING.md`.
- [ADR-0007](docs/decisions/0007-publish-without-destroying-what-you-did-not-create.md),
  recording why publishing touches only what it published: copy rather than
  sync with delete, no ACL by default, explicit content types, and invalidation
  scoped to the prefix. Each looks like an oversight to a reader assuming a
  dedicated bucket, and each is destructive if "corrected".

## [1.0.0] - 2026-08-31

### Added

- `build-pandoc`, `build-zensical` and `build-sphinx` actions, one per
  documentation generator. Only the build step differs between them; see
  [ADR-0003](docs/decisions/0003-one-build-action-per-generator.md).
- `index-site` action, building a Pagefind index over already-built HTML, so
  it works with any generator.
- `deploy-site` action, which refuses to publish a build containing no HTML or
  no `index.html` before uploading it as a Pages artifact.
- `docs-pandoc.yml` reusable workflow, wrapping the common build, index and
  deploy sequence.
- The shared Caltech Pandoc theme in `pandoc/`, overridable per project.
- Architecture decision records in `docs/decisions/`.

[Unreleased]: https://github.com/caltechlibrary/workflows/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/caltechlibrary/workflows/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/caltechlibrary/workflows/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/caltechlibrary/workflows/releases/tag/v1.0.0
