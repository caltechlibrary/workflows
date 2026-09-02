#!/usr/bin/env bash
#
# Upload built assets to an S3 bucket behind CloudFront, then invalidate the
# paths that changed.
#
# Credentials are not handled here. The caller is expected to have configured
# them already -- in CI that means OIDC via aws-actions/configure-aws-credentials,
# so no long-lived keys exist anywhere. Locally it means whatever profile you
# normally use.
#
#   publish-to-s3.sh --bucket my-bucket --prefix my-project \
#                  --source dist --source css --distribution E123 --dry-run
#
# Always run --dry-run first. It prints what would be uploaded and what would
# be invalidated, and touches nothing.

set -euo pipefail

BUCKET=""
PREFIX=""
DISTRIBUTION=""
DRY_RUN="false"
ACL="none"
MANIFEST=""
VERIFY_URL=""
declare -a SOURCES=()

usage() {
  cat <<'USAGE'
publish-to-s3.sh -- sync built assets to S3 and invalidate CloudFront

Options:
  --bucket NAME         S3 bucket                              (required)
  --prefix PATH         key prefix within the bucket; omit to
                        publish to the bucket root
  --source DIR          directory to upload, repeatable        (required)
  --distribution ID     CloudFront distribution to invalidate  (optional)
  --acl ACL             object ACL, or "none"                  (default: none)
  --verify-url URL      after publishing, fetch one published file from here
                        and fail if it is not readable
  --manifest FILE       write the published keys, one per line, for a caller
                        that wants to report or link them
  --dry-run             show what would happen, change nothing
  -h, --help            this text
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --bucket)       BUCKET="$2"; shift 2 ;;
    --prefix)       PREFIX="$2"; shift 2 ;;
    --source)       SOURCES+=("$2"); shift 2 ;;
    --distribution) DISTRIBUTION="$2"; shift 2 ;;
    --acl)          ACL="$2"; shift 2 ;;
    --manifest)     MANIFEST="$2"; shift 2 ;;
    --verify-url)   VERIFY_URL="$2"; shift 2 ;;
    --dry-run)      DRY_RUN="true"; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "publish-to-s3: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$BUCKET" ] || { echo "publish-to-s3: --bucket is required" >&2; exit 2; }
[ ${#SOURCES[@]} -gt 0 ] || { echo "publish-to-s3: at least one --source is required" >&2; exit 2; }
command -v aws >/dev/null || { echo "publish-to-s3: the AWS CLI is not installed" >&2; exit 1; }

# Refuse to publish nothing. An empty build that "succeeds" would otherwise
# leave the CDN serving whatever was there before, with no signal.
for dir in "${SOURCES[@]}"; do
  [ -d "$dir" ] || { echo "publish-to-s3: no such directory: $dir" >&2; exit 1; }
  [ -n "$(find "$dir" -type f -print -quit)" ] || {
    echo "publish-to-s3: $dir is empty" >&2; exit 1; }
done

# An empty prefix means the bucket root, which is the shape a project gets
# when it has a bucket to itself.
PREFIX="${PREFIX#/}"; PREFIX="${PREFIX%/}"
BASE="s3://$BUCKET"
[ -n "$PREFIX" ] && BASE="$BASE/$PREFIX"
declare -a EXTRA=()
[ "$DRY_RUN" = "true" ] && EXTRA+=("--dryrun")
# AWS recommends ACLs disabled and access granted by bucket policy, so no ACL
# is the default. A bucket still in legacy ObjectWriter mode with no policy
# needs --acl public-read, or its objects upload fine and are unreadable.
[ "$ACL" != "none" ] && EXTRA+=("--acl" "$ACL")

# Content types are set explicitly rather than left to the CLI's guess. The
# guess omits the charset and can differ by CLI version, which would silently
# change what the CDN serves for files nobody edited.
content_type_for() {
  case "$1" in
    js)          echo "text/javascript; charset=utf-8" ;;
    css)         echo "text/css; charset=utf-8" ;;
    json)        echo "application/json; charset=utf-8" ;;
    jsonld)      echo "application/ld+json; charset=utf-8" ;;
    svg)         echo "image/svg+xml; charset=utf-8" ;;
    woff)        echo "font/woff" ;;
    woff2)       echo "font/woff2" ;;
    map)         echo "application/json; charset=utf-8" ;;
    *)           echo "" ;;
  esac
}

# NOTE: `cp`, not `sync --delete`. A bucket commonly holds objects no
# repository produces, and a delete-enabled sync removes them with nothing to
# put them back. See ADR-0007.
[ -n "$MANIFEST" ] && : > "$MANIFEST"

for dir in "${SOURCES[@]}"; do
  dest="$BASE/$(basename "$dir")/"
  # dist/ holds the bundles themselves, which belong at the prefix root
  [ "$(basename "$dir")" = "dist" ] && dest="$BASE/"
  echo "==> $dir -> $dest"

  # One pass per extension we have a content type for, then a final pass for
  # everything else. The final pass is a no-op when nothing is left over.
  declare -a SKIP=()
  while IFS= read -r ext; do
    [ -n "$ext" ] || continue
    ct="$(content_type_for "$ext")"
    [ -n "$ct" ] || continue
    SKIP+=("--exclude" "*.$ext")
    aws s3 cp "$dir/" "$dest" --recursive \
      --exclude "*" --include "*.$ext" --content-type "$ct" \
      ${EXTRA[@]+"${EXTRA[@]}"}
  done <<< "$(find "$dir" -type f -name '*.*' | sed 's|.*/||; s|.*\.||' | sort -u)"

  aws s3 cp "$dir/" "$dest" --recursive \
    ${SKIP[@]+"${SKIP[@]}"} ${EXTRA[@]+"${EXTRA[@]}"}

  # Keys published, relative to the prefix.
  if [ -n "$MANIFEST" ]; then
    sub=""
    [ "$(basename "$dir")" = "dist" ] || sub="$(basename "$dir")/"
    ( cd "$dir" && find . -type f | sed "s|^\./|$sub|" ) >> "$MANIFEST"
  fi
done

if [ -n "$DISTRIBUTION" ]; then
  # Scoped to this project's prefix. Invalidating /* would charge for and
  # discard every other site's cached objects in the same distribution.
  if [ -n "$PREFIX" ]; then
    PATHS="/$PREFIX/*"
  else
    PATHS="/*"
    echo "note: no prefix, so this invalidates the whole distribution" >&2
  fi
  if [ "$DRY_RUN" = "true" ]; then
    echo "==> would invalidate $PATHS on $DISTRIBUTION"
  else
    echo "==> invalidating $PATHS on $DISTRIBUTION"
    aws cloudfront create-invalidation \
      --distribution-id "$DISTRIBUTION" --paths "$PATHS" \
      --query 'Invalidation.{Id:Id,Status:Status}' --output text
  fi
fi

# An object uploaded without the ACL a legacy bucket needs succeeds and is
# then unreadable. Fetching one published file turns that into a failure here
# rather than a report from someone whose page stopped working.
if [ -n "$VERIFY_URL" ] && [ "$DRY_RUN" != "true" ] && [ -n "$MANIFEST" ]; then
  key="$(head -n 1 "$MANIFEST")"
  if [ -n "$key" ]; then
    url="${VERIFY_URL%/}/$key"
    code="$(curl -s -o /dev/null -w '%{http_code}' -L "$url" || echo 000)"
    if [ "$code" = "200" ]; then
      echo "verified: $url is readable"
    else
      echo "publish-to-s3: published, but $url returned $code" >&2
      echo "  if this is 403, the bucket likely needs --acl public-read" >&2
      exit 1
    fi
  fi
fi

echo "publish-to-s3: ${DRY_RUN:+dry run }done"
