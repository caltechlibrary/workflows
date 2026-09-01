#!/usr/bin/env bash
#
# Build a documentation site with Zensical.
#
# Zensical takes its output directory from the config file rather than a flag,
# and defaults to site/. Everything downstream in this repository expects
# _site/, so this relocates the result when the two differ. That keeps the
# build/deploy seam identical no matter which generator ran.
#
#   build-zensical.sh --output _site
#
# Zensical reads zensical.toml or mkdocs.yml, so a project migrating from
# MkDocs can point this at its existing config.

set -euo pipefail

OUTPUT="_site"
SITE_DIR="site"
CONFIG=""
CLEAN="true"
STRICT="false"

usage() {
  cat <<'USAGE'
build-zensical.sh -- build a documentation site with Zensical

Options:
  --output DIR      where the site should end up      (default: _site)
  --site-dir DIR    where Zensical writes it, if the
                    config overrides the default      (default: site)
  --config FILE     zensical.toml or mkdocs.yml       (default: auto)
  --no-clean        keep the build cache
  --strict          abort the build on warnings
  -h, --help        this text
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --output)    OUTPUT="$2"; shift 2 ;;
    --site-dir)  SITE_DIR="$2"; shift 2 ;;
    --config)    CONFIG="$2"; shift 2 ;;
    --no-clean)  CLEAN="false"; shift ;;
    --strict)    STRICT="true"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "build-zensical: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v zensical >/dev/null || {
  echo "build-zensical: zensical is not installed (pip install zensical)" >&2
  exit 1
}

declare -a ARGS=("build")
[ -n "$CONFIG" ]      && ARGS+=("--config-file" "$CONFIG")
[ "$CLEAN"  = "true" ] && ARGS+=("--clean")
[ "$STRICT" = "true" ] && ARGS+=("--strict")

echo "zensical ${ARGS[*]}"
zensical "${ARGS[@]}"

[ -d "$SITE_DIR" ] || {
  echo "build-zensical: zensical did not write $SITE_DIR" >&2
  echo "  if the config sets site_dir, pass --site-dir to match" >&2
  exit 1
}

if [ "$SITE_DIR" != "$OUTPUT" ]; then
  rm -rf "$OUTPUT"
  mv "$SITE_DIR" "$OUTPUT"
fi

PAGES="$(find "$OUTPUT" -name '*.html' | wc -l | tr -d ' ')"
[ "$PAGES" -gt 0 ] || { echo "build-zensical: $OUTPUT contains no HTML" >&2; exit 1; }
echo "build-zensical: $PAGES page(s) into $OUTPUT"
