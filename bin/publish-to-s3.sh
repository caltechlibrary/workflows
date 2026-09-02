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
#   publish-to-s3.sh --bucket my-bucket --prefix cl-webcomponents \
#                  --source dist --source css --distribution E123 --dry-run
#
# Always run --dry-run first. It prints what would be uploaded and what would
# be invalidated, and touches nothing.

set -euo pipefail

BUCKET=""
PREFIX=""
DISTRIBUTION=""
DRY_RUN="false"
ACL="public-read"
MANIFEST=""
declare -a SOURCES=()

usage() {
  cat <<'USAGE'
publish-to-s3.sh -- sync built assets to S3 and invalidate CloudFront

Options:
  --bucket NAME         S3 bucket                              (required)
  --prefix PATH         key prefix within the bucket           (required)
  --source DIR          directory to upload, repeatable        (required)
  --distribution ID     CloudFront distribution to invalidate  (optional)
  --acl ACL             object ACL, or "none" to omit          (default: public-read)
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
    --dry-run)      DRY_RUN="true"; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "publish-to-s3: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$BUCKET" ] || { echo "publish-to-s3: --bucket is required" >&2; exit 2; }
[ -n "$PREFIX" ] || { echo "publish-to-s3: --prefix is required" >&2; exit 2; }
[ ${#SOURCES[@]} -gt 0 ] || { echo "publish-to-s3: at least one --source is required" >&2; exit 2; }
command -v aws >/dev/null || { echo "publish-to-s3: the AWS CLI is not installed" >&2; exit 1; }

# Refuse to publish nothing. An empty build that "succeeds" would otherwise
# leave the CDN serving whatever was there before, with no signal.
for dir in "${SOURCES[@]}"; do
  [ -d "$dir" ] || { echo "publish-to-s3: no such directory: $dir" >&2; exit 1; }
  [ -n "$(find "$dir" -type f -print -quit)" ] || {
    echo "publish-to-s3: $dir is empty" >&2; exit 1; }
done

PREFIX="${PREFIX%/}"
declare -a EXTRA=()
[ "$DRY_RUN" = "true" ] && EXTRA+=("--dryrun")
# The bucket is in legacy ObjectWriter mode with no bucket policy: public read
# comes entirely from per-object ACLs. Dropping this makes uploads invisible.
# Removing the need for it means adding a bucket policy first -- see the
# media bucket notes before changing this.
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

# NOTE: this uses `cp`, not `sync --delete`. The bucket holds objects this
# repository does not manage -- fonts/ among them -- and a delete-enabled sync
# would remove them. Do not "improve" this to a sync without checking what else
# lives under the prefix.
[ -n "$MANIFEST" ] && : > "$MANIFEST"

for dir in "${SOURCES[@]}"; do
  dest="s3://$BUCKET/$PREFIX/$(basename "$dir")/"
  # dist/ holds the bundles themselves, which belong at the prefix root
  [ "$(basename "$dir")" = "dist" ] && dest="s3://$BUCKET/$PREFIX/"
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
  PATHS="/$PREFIX/*"
  if [ "$DRY_RUN" = "true" ]; then
    echo "==> would invalidate $PATHS on $DISTRIBUTION"
  else
    echo "==> invalidating $PATHS on $DISTRIBUTION"
    aws cloudfront create-invalidation \
      --distribution-id "$DISTRIBUTION" --paths "$PATHS" \
      --query 'Invalidation.{Id:Id,Status:Status}' --output text
  fi
fi

echo "publish-to-s3: ${DRY_RUN:+dry run }done"
