#!/usr/bin/env bash
#
# Tag a commit and open a draft GitHub release for it, with artifacts attached.
#
# Draft, always. Publishing is a human act: someone reads the notes, checks the
# artifacts, and presses the button. Nothing here publishes, and nothing here
# decides a version -- the caller has already bumped whatever holds it and
# committed that, so this tags what is in front of it.
#
#   create-release.sh --tag v1.2.3 --notes-file notes.md --artifact dist/app.zip
#
# Authentication is not handled here. The caller is expected to have gh
# authenticated already -- in CI that is GH_TOKEN, locally it is your own
# gh login.

set -euo pipefail

TAG=""
TITLE=""
NOTES_FILE=""
TARGET=""
DRY_RUN="false"
GENERATE_NOTES="true"
declare -a ARTIFACTS=()

usage() {
  cat <<'USAGE'
create-release.sh -- tag a commit and open a draft GitHub release

Options:
  --tag NAME            tag to create, e.g. v1.2.3                (required)
  --title TEXT          release title                    (default: the tag)
  --notes-file FILE     Markdown prepended to the generated notes
  --target SHA          commit to tag                     (default: HEAD)
  --artifact PATH       file to attach, repeatable
  --no-generate-notes   omit GitHub's commit-derived notes
  --dry-run             show what would happen, change nothing
  -h, --help            this text
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tag)                TAG="$2"; shift 2 ;;
    --title)              TITLE="$2"; shift 2 ;;
    --notes-file)         NOTES_FILE="$2"; shift 2 ;;
    --target)             TARGET="$2"; shift 2 ;;
    --artifact)           ARTIFACTS+=("$2"); shift 2 ;;
    --no-generate-notes)  GENERATE_NOTES="false"; shift ;;
    --dry-run)            DRY_RUN="true"; shift ;;
    -h|--help)            usage; exit 0 ;;
    *) echo "create-release: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$TAG" ] || { echo "create-release: --tag is required" >&2; exit 2; }
command -v gh >/dev/null || { echo "create-release: gh is not installed" >&2; exit 1; }

[ -n "$TITLE" ] || TITLE="$TAG"
[ -n "$TARGET" ] || TARGET="$(git rev-parse HEAD)"

if [ -n "$NOTES_FILE" ] && [ ! -f "$NOTES_FILE" ]; then
  echo "create-release: no such file: $NOTES_FILE" >&2
  exit 1
fi

# An empty or missing artifact means the build silently produced nothing, which
# is the failure worth catching -- a release with no files looks fine until
# someone tries to download one.
for f in ${ARTIFACTS[@]+"${ARTIFACTS[@]}"}; do
  [ -f "$f" ] || { echo "create-release: no such artifact: $f" >&2; exit 1; }
  [ -s "$f" ] || { echo "create-release: artifact is empty: $f" >&2; exit 1; }
done

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "create-release: tag already exists: $TAG" >&2
  exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "create-release: a release already exists for $TAG" >&2
  exit 1
fi

declare -a ARGS=("$TAG" --draft --title "$TITLE" --target "$TARGET")
[ "$GENERATE_NOTES" = "true" ] && ARGS+=(--generate-notes)
[ -n "$NOTES_FILE" ] && ARGS+=(--notes-file "$NOTES_FILE")
for f in ${ARTIFACTS[@]+"${ARTIFACTS[@]}"}; do ARGS+=("$f"); done

echo "tag:       $TAG"
echo "target:    $TARGET"
echo "title:     $TITLE"
echo "artifacts: ${#ARTIFACTS[@]}"
for f in ${ARTIFACTS[@]+"${ARTIFACTS[@]}"}; do echo "  $f"; done

if [ "$DRY_RUN" = "true" ]; then
  echo "==> would run: gh release create ${ARGS[*]}"
  echo "create-release: dry run, nothing created"
  exit 0
fi

gh release create "${ARGS[@]}"

URL="$(gh release view "$TAG" --json url --jq .url)"
echo "create-release: draft created, publish it at $URL"
