#!/usr/bin/env bash
#
# Render a Markdown documentation directory into a static site with Pandoc.
#
# Search indexing is a separate step (bin/index-site.sh) because it works on
# built HTML and so applies to any generator, not just this one.
#
# This is the script GitHub Actions runs. It takes no GitHub context and reads
# no CI environment, so running it on your own machine produces the same site
# CI publishes -- it is the same file, not a reimplementation.
#
#   build-pandoc.sh --docs-dir docs --output _site
#
# Defaults for the template and Lua filters resolve to this repository's
# pandoc/ directory, so a project gets the shared Caltech theme without
# copying it. Pass --template or --lua-filter to override.
#
# The theme's own CSS and JS are copied into the site from pandoc/css and
# pandoc/js, so a published site serves them itself rather than fetching them
# from somewhere else. Projects add their own with --extra-css/--extra-js,
# which load after the theme's; for CSS that is enough to override any of it,
# because later rules win. Nothing needs to be forked to be customized.
#
# --site-base prefixes those URLs. It has no default here because this script
# knows nothing about where a site is published; the action supplies one.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DOCS_DIR="docs"
OUTPUT="_site"
TEMPLATE="$HERE/pandoc/page.tmpl"
INDEX_FROM="README"
PROJECT=""
REPO_URL=""
SEARCH_PAGE=""
SITE_BASE=""
declare -a EXTRA_CSS=()
declare -a EXTRA_JS=()
declare -a LUA_FILTERS=()
declare -a EXTRA_SOURCES=()
declare -a INCLUDE=()

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'USAGE'
Options:
  --docs-dir DIR        Markdown sources             (default: docs)
  --output DIR          site output                  (default: _site)
  --template FILE       Pandoc template              (default: shared theme)
  --lua-filter FILE     repeatable                   (default: shared filters)
  --extra-source PATH   Markdown outside --docs-dir, repeatable
  --include PATH        file or directory to copy into the site, repeatable
  --site-base PREFIX    URL prefix for theme assets, e.g. /my-repo/
  --extra-css FILE      stylesheet to ship and load after the theme, repeatable
  --extra-js FILE       script to ship and load after the theme, repeatable
  --index-from BASE     basename that becomes index.html (default: README)
  --project NAME        site name for the theme
  --repo-url URL        repository link for the theme
  --search              add a Search item to the theme's nav
  -h, --help            this text
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --docs-dir)     DOCS_DIR="$2"; shift 2 ;;
    --output)       OUTPUT="$2"; shift 2 ;;
    --template)     TEMPLATE="$2"; shift 2 ;;
    --lua-filter)   LUA_FILTERS+=("$2"); shift 2 ;;
    --extra-source) EXTRA_SOURCES+=("$2"); shift 2 ;;
    --include)      INCLUDE+=("$2"); shift 2 ;;
    --site-base)    SITE_BASE="$2"; shift 2 ;;
    --extra-css)    EXTRA_CSS+=("$2"); shift 2 ;;
    --extra-js)     EXTRA_JS+=("$2"); shift 2 ;;
    --index-from)   INDEX_FROM="$2"; shift 2 ;;
    --project)      PROJECT="$2"; shift 2 ;;
    --repo-url)     REPO_URL="$2"; shift 2 ;;
    --search)       SEARCH_PAGE="true"; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "build-pandoc: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Shared filters only when the caller named none, so --lua-filter replaces
# rather than appends to the defaults.
if [ ${#LUA_FILTERS[@]} -eq 0 ]; then
  LUA_FILTERS=("$HERE/pandoc/links-to-html.lua" "$HERE/pandoc/add-col-scope.lua")
fi

for f in "$TEMPLATE" "${LUA_FILTERS[@]}" \
         ${EXTRA_CSS[@]+"${EXTRA_CSS[@]}"} ${EXTRA_JS[@]+"${EXTRA_JS[@]}"}; do
  [ -f "$f" ] || { echo "build-pandoc: no such file: $f" >&2; exit 1; }
done
[ -d "$DOCS_DIR" ] || { echo "build-pandoc: no such directory: $DOCS_DIR" >&2; exit 1; }

command -v pandoc >/dev/null || { echo "build-pandoc: pandoc is not installed" >&2; exit 1; }

mkdir -p "$OUTPUT"

declare -a PANDOC_ARGS=("--standalone" "--to=html5" "--template=$TEMPLATE")
for f in "${LUA_FILTERS[@]}"; do PANDOC_ARGS+=("--lua-filter=$f"); done
[ -n "$PROJECT" ]  && PANDOC_ARGS+=("--variable=project:$PROJECT")
[ -n "$REPO_URL" ] && PANDOC_ARGS+=("--variable=repo-url:$REPO_URL")
[ -n "$SEARCH_PAGE" ] && PANDOC_ARGS+=("--variable=search:true")
[ -n "$SITE_BASE" ] && PANDOC_ARGS+=("--variable=site-base:$SITE_BASE")
# The template composes the path, so it only needs the filename.
for f in ${EXTRA_CSS[@]+"${EXTRA_CSS[@]}"}; do
  PANDOC_ARGS+=("--variable=extra-css:$(basename "$f")")
done
for f in ${EXTRA_JS[@]+"${EXTRA_JS[@]}"}; do
  PANDOC_ARGS+=("--variable=extra-js:$(basename "$f")")
done

rendered=0
render_one() {
  local src="$1" base out title
  base="$(basename "$src" .md)"
  out="$OUTPUT/$base.html"
  title="$base"
  if [ "$base" = "$INDEX_FROM" ]; then
    out="$OUTPUT/index.html"
    title="Home"
  fi
  echo "  $src -> $out"
  pandoc "${PANDOC_ARGS[@]}" --metadata "title=$title" "$src" -o "$out"
  rendered=$((rendered + 1))
}

echo "Rendering Markdown"
for src in "$DOCS_DIR"/*.md; do
  [ -e "$src" ] || continue
  render_one "$src"
done
for pattern in ${EXTRA_SOURCES[@]+"${EXTRA_SOURCES[@]}"}; do
  # shellcheck disable=SC2086 # the caller supplies a glob on purpose
  for src in $pattern; do
    [ -e "$src" ] || continue
    render_one "$src"
  done
done

if [ "$rendered" -eq 0 ]; then
  echo "build-pandoc: no Markdown found in $DOCS_DIR" >&2
  exit 1
fi

# Demo and test pages ship as-is; they are sources, not generated output.
shopt -s nullglob
for html in "$DOCS_DIR"/*.html; do cp -p "$html" "$OUTPUT/"; done
shopt -u nullglob

# The theme's assets, then the project's on top. A project file with the same
# name as a theme file replaces it, which works but forks it -- prefer a new
# file and let the cascade do the work.
for dir in css js; do
  [ -d "$HERE/pandoc/$dir" ] || continue
  mkdir -p "$OUTPUT/$dir"
  cp -p "$HERE/pandoc/$dir"/* "$OUTPUT/$dir/"
done
for f in ${EXTRA_CSS[@]+"${EXTRA_CSS[@]}"}; do
  mkdir -p "$OUTPUT/css"; cp -p "$f" "$OUTPUT/css/"
done
for f in ${EXTRA_JS[@]+"${EXTRA_JS[@]}"}; do
  mkdir -p "$OUTPUT/js"; cp -p "$f" "$OUTPUT/js/"
done

for path in ${INCLUDE[@]+"${INCLUDE[@]}"}; do
  # shellcheck disable=SC2086 # likewise
  for item in $path; do
    [ -e "$item" ] || { echo "build-pandoc: --include not found: $item" >&2; exit 1; }
    cp -Rp "$item" "$OUTPUT/"
  done
done


echo "build-pandoc: $rendered page(s) into $OUTPUT"
