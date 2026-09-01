#!/usr/bin/env bash
#
# Build a Pagefind search index for an already-built site.
#
# This works on the output HTML, so it does not care which generator produced
# it -- Pandoc, Sphinx, or anything else that writes a directory of pages.
# Generators with their own search (Zensical, Material) do not need it.
#
#   index-site.sh --site _site

set -euo pipefail

SITE="_site"
declare -a EXCLUDE=()

usage() {
  cat <<'USAGE'
index-site.sh -- build a Pagefind search index for a built site

Options:
  --site DIR             the built site                (default: _site)
  --exclude-selector SEL CSS to keep out of the index, repeatable
                         (default: nav, header, footer)
  -h, --help             this text
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --site)              SITE="$2"; shift 2 ;;
    --exclude-selector)  EXCLUDE+=("$2"); shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "index-site: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -d "$SITE" ] || { echo "index-site: no such directory: $SITE" >&2; exit 1; }
command -v pagefind >/dev/null || { echo "index-site: pagefind is not installed" >&2; exit 1; }

if [ ${#EXCLUDE[@]} -eq 0 ]; then
  EXCLUDE=("nav" "header" "footer")
fi
SELECTORS="$(IFS=,; echo "${EXCLUDE[*]}")"

pagefind --site "$SITE" --force-language en-US --exclude-selectors "$SELECTORS"
