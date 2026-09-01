#!/usr/bin/env bash
#
# Build a documentation site with Sphinx.
#
# Sphinx writes to docs/_build/html by convention. Everything downstream in
# this repository expects _site/, so this relocates the result. That keeps the
# build/deploy seam identical no matter which generator ran.
#
#   build-sphinx.sh --docs-dir docs --output _site
#
# Dependencies are the project's business: Sphinx builds are sensitive to
# extension and theme versions, so this installs nothing. Install them before
# calling, or let the build-sphinx action do it from a requirements file.

set -euo pipefail

DOCS_DIR="docs"
OUTPUT="_site"
BUILDER="html"
STRICT="false"
declare -a EXTRA=()

usage() {
  cat <<'USAGE'
build-sphinx.sh -- build a documentation site with Sphinx

Options:
  --docs-dir DIR    directory holding conf.py     (default: docs)
  --output DIR      where the site should end up  (default: _site)
  --builder NAME    sphinx builder                (default: html)
  --strict          treat warnings as errors (-W)
  --               everything after this is passed to sphinx-build
  -h, --help        this text
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --docs-dir)  DOCS_DIR="$2"; shift 2 ;;
    --output)    OUTPUT="$2"; shift 2 ;;
    --builder)   BUILDER="$2"; shift 2 ;;
    --strict)    STRICT="true"; shift ;;
    --)          shift; EXTRA=("$@"); break ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "build-sphinx: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v sphinx-build >/dev/null || {
  echo "build-sphinx: sphinx-build is not installed" >&2
  echo "  install the project's documentation requirements first" >&2
  exit 1
}
[ -f "$DOCS_DIR/conf.py" ] || {
  echo "build-sphinx: no conf.py in $DOCS_DIR" >&2
  exit 1
}

declare -a ARGS=("-b" "$BUILDER")
[ "$STRICT" = "true" ] && ARGS+=("-W")

# Build straight into the destination. Going via docs/_build/html would leave
# build output inside the source tree, which is how generated files end up
# committed.
echo "sphinx-build ${ARGS[*]} $DOCS_DIR $OUTPUT"
rm -rf "$OUTPUT"
sphinx-build "${ARGS[@]}" ${EXTRA[@]+"${EXTRA[@]}"} "$DOCS_DIR" "$OUTPUT"

PAGES="$(find "$OUTPUT" -name '*.html' | wc -l | tr -d ' ')"
[ "$PAGES" -gt 0 ] || { echo "build-sphinx: $OUTPUT contains no HTML" >&2; exit 1; }

# Sphinx emits .doctrees alongside the site unless told otherwise; it is build
# state, not something to publish.
rm -rf "$OUTPUT/.doctrees"

echo "build-sphinx: $PAGES page(s) into $OUTPUT"
