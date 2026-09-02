# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Consuming repositories reference a **moving major tag** such as `@v1`, which
advances with every backward-compatible change. This file is how you find out
what moved. See
[ADR-0006](docs/decisions/0006-version-with-moving-major-tags.md).

## [Unreleased]

### Added

- `CHANGELOG.md`, following
  [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- [ADR-0007](docs/decisions/0007-publish-without-destroying-what-you-did-not-create.md),
  recording why publishing touches only what it published: copy rather than
  sync with delete, no ACL by default, explicit content types, and invalidation
  scoped to the prefix. Each looks like an oversight to a reader assuming a
  dedicated bucket, and each is destructive if "corrected".

### Changed

- `publish-to-s3`: `prefix` is now optional. An empty prefix publishes to the
  bucket root and invalidates the whole distribution, which is correct for a
  bucket belonging to one project. The script reports when that happens.
- `publish-to-s3`: **the `acl` default is now `none`**, following AWS's
  recommendation to disable ACLs and grant access by bucket policy. A bucket
  in legacy `ObjectWriter` mode with no policy must now set
  `acl: public-read` explicitly.
- `publish-to-s3`: when `public-base-url` is set, one published file is
  fetched after a real publish and a non-200 fails the job. An object uploaded
  without an ACL a legacy bucket needs otherwise succeeds and is silently
  unreadable.

### Fixed

- `publish-to-s3` no longer fails after a successful publish when 40 or fewer
  files are uploaded. The summary step ended on a test that returns non-zero
  when false, and composite action steps run with `bash -eo pipefail`.

## [1.1.0] - 2026-09-01

### Added

- `publish-to-s3` action: uploads built assets to S3 and invalidates the
  matching CloudFront paths, authenticating with OIDC so no long-lived AWS
  keys are required. Replaces per-repository `publish_to_s3.bash` and
  `invalidate_cdn.bash` scripts.
- `public-base-url` input on `publish-to-s3`, which turns the job summary into
  links to each published file. S3 website endpoints serve no directory
  listing, so the files have to be named individually.

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

[Unreleased]: https://github.com/caltechlibrary/workflows/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/caltechlibrary/workflows/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/caltechlibrary/workflows/releases/tag/v1.0.0
