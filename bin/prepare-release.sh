#!/usr/bin/env bash
#
# Set a new version everywhere a project records one, and turn the
# [Unreleased] section of its changelog into that version’s section.
#
#   prepare-release.sh minor          # 1.4.2 -> 1.5.0
#   prepare-release.sh 2.0.0
#
# Give a version, or major, minor, or patch to bump the current one. The
# current version is read from every file below that carries one; they must
# agree, and the new version must be greater than it and than every existing
# vX.Y.Z tag.
#
#   CHANGELOG.md     required. [Unreleased] must have entries; it becomes
#                    "## [X.Y.Z] - DATE" under a new, empty [Unreleased], and
#                    the compare links at the bottom are updated if present
#   pyproject.toml   [project] version, when it is a literal
#   setup.cfg        [metadata] version, when it is a literal
#   __init__.py      __version__ in <package>/ or src/<package>/
#   uv.lock          the project’s own [[package]] version
#   codemeta.json    "version", and "datePublished" (added if absent)
#   CITATION.cff     version: and date-released:
#
# A file that is absent, or carries no literal version, is skipped. Nothing is
# written unless every check passes. This edits the working tree and does
# nothing else: it doesn’t commit, tag, push, or talk to GitHub. "git diff"
# shows the result and "git checkout ." undoes it.
#
# On success it prints, on stdout, lines a caller can read:
#
#   previous=1.4.2
#   version=1.5.0
#   tag=v1.5.0
#
# Progress and errors go to stderr. Runs on the bash 3.2 macOS ships.
#
# Needs bash, git, jq, awk, and sed.

set -euo pipefail

PROJECT_DIR="."
REQUEST=""
NOTES=""
TODAY=""

usage() {
  cat <<'USAGE'
prepare-release.sh -- set a new version in every file that records one, and
date the changelog's [Unreleased] section

Usage: prepare-release.sh [options] VERSION|major|minor|patch

Options:
  --project-dir DIR   the project to release                   (default: .)
  --date DATE         release date, YYYY-MM-DD   (default: today, in $TZ)
  --notes FILE        also write the new changelog section's body to FILE
  -h, --help          this text
USAGE
}

say() { echo "prepare-release: $*" >&2; }
die() { say "$*"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --date)        TODAY="$2"; shift 2 ;;
    --notes)       NOTES="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    -*)            say "unknown option: $1"; usage >&2; exit 2 ;;
    *)             [ -z "$REQUEST" ] || { usage >&2; exit 2; }; REQUEST="$1"; shift ;;
  esac
done

[ -n "$REQUEST" ] || { usage >&2; exit 2; }
for p in git jq awk sed; do
  command -v "$p" >/dev/null || die "$p is not installed"
done
[ -d "$PROJECT_DIR" ] || die "no such directory: $PROJECT_DIR"
# The notes file is written after the cd below, so pin its path down first.
if [ -n "$NOTES" ]; then
  NOTES="$(cd "$(dirname "$NOTES")" && pwd)/$(basename "$NOTES")"
fi
cd "$PROJECT_DIR"
[ -n "$TODAY" ] || TODAY="$(date +%F)"
[[ "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || die "date must look like 2026-01-31, not \"$TODAY\""
[ -f CHANGELOG.md ] || die "no CHANGELOG.md in $(pwd)"

SEMVER='^[0-9]+\.[0-9]+\.[0-9]+$'

# Succeeds if version $1 is greater than version $2.
newer() {
  local a b i
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for i in 0 1 2; do
    [ "${a[$i]}" -gt "${b[$i]}" ] && return 0
    [ "${a[$i]}" -lt "${b[$i]}" ] && return 1
  done
  return 1
}

# Reading and writing ────────────────────────────────────────────────────────

# TOML and INI tables. HEADER is the table’s header line exactly, such as
# [project] or [[package]]; for an array of tables, NAME picks the one whose
# `name` has that value (empty for any). A table runs to the next line that
# starts with "[".
#
#   table_get FILE HEADER KEY NAME        print the value of KEY
#   table_set HEADER KEY NAME VALUE FILE  print FILE with KEY’s value replaced
#
# Values may be quoted or bare; table_set keeps whichever the line had.
TABLE_AWK='
  function value(line) {
    sub(/^[^=]*=[ \t]*/, "", line); sub(/[ \t]*$/, "", line)
    gsub(/^"|"$/, "", line); return line
  }
  function is_key(line, k) { return line ~ ("^" k "[ \t]*=") }
'

table_get() {
  awk -v header="$2" -v key="$3" -v name="$4" "$TABLE_AWK"'
    function finish() {
      if (inside && named && found != "" && !printed) { print found; printed = 1 }
    }
    $0 == header { finish(); inside = 1; named = (name == ""); found = ""; next }
    /^\[/        { finish(); inside = 0; next }
    inside && is_key($0, "name") && value($0) == name { named = 1 }
    inside && is_key($0, key)                         { found = value($0) }
    END          { finish() }
  ' "$1"
}

table_set() {
  awk -v header="$1" -v key="$2" -v name="$3" -v new="$4" "$TABLE_AWK"'
    function flush(   i, line) {
      for (i = 1; i <= n; i++) {
        line = buf[i]
        if (named && is_key(line, key)) {
          if (line ~ /"/) sub(/"[^"]*"/, "\"" new "\"", line)
          else            sub(/=[ \t]*.*$/, "= " new, line)
        }
        print line
      }
      n = 0
    }
    $0 == header { flush(); inside = 1; named = (name == ""); print; next }
    /^\[/        { flush(); inside = 0; print; next }
    inside       { buf[++n] = $0; if (is_key($0, "name") && value($0) == name) named = 1; next }
                 { print }
    END          { flush() }
  ' "$5"
}

# Every edit is made to a copy in $STAGE, and the copies replace the real
# files only once every one of them has been made and checked.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
staged() {
  if [ ! -f "$STAGE/$1" ]; then
    mkdir -p "$STAGE/$(dirname "$1")"
    cp "$1" "$STAGE/$1"
  fi
  echo "$STAGE/$1"
}
# Replace staged file $1 with the output of the rest, run with it appended.
rewrite() {
  local file
  file="$(staged "$1")"; shift
  "$@" "$file" > "$file.new"
  mv "$file.new" "$file"
}

# Find the current version ───────────────────────────────────────────────────

FILES=()      # files that carry a version
VERSIONS=()   # the version each one carries, in the same order

record() {
  if [[ "$2" =~ $SEMVER ]]; then
    FILES+=("$1"); VERSIONS+=("$2")
  elif [ -n "$2" ]; then
    say "skipping $1: \"$2\" is not a literal X.Y.Z version"
  fi
}

QUOTED='["'\'']?([^"'\'' ]*)["'\'']?'   # a value in optional quotes, captured
NAME=""
INIT=""
LOCK_NAME=""
if [ -f pyproject.toml ]; then
  NAME="$(table_get pyproject.toml '[project]' name '')"
  record pyproject.toml "$(table_get pyproject.toml '[project]' version '')"
fi
if [ -f setup.cfg ]; then
  [ -n "$NAME" ] || NAME="$(table_get setup.cfg '[metadata]' name '')"
  record setup.cfg "$(table_get setup.cfg '[metadata]' version '')"
fi
if [ -n "$NAME" ]; then
  package="$(tr '[:upper:]' '[:lower:]' <<< "$NAME" | sed -E 's/[-.]+/_/g')"
  for candidate in "$package/__init__.py" "src/$package/__init__.py"; do
    if [ -f "$candidate" ]; then INIT="$candidate"; break; fi
  done
  if [ -n "$INIT" ]; then
    record "$INIT" "$(sed -nE "s/^__version__[[:blank:]]*=[[:blank:]]*${QUOTED}.*/\1/p" "$INIT" | head -1)"
  fi
  if [ -f uv.lock ]; then
    # uv’s normalized form of the project name.
    LOCK_NAME="$(tr '[:upper:]' '[:lower:]' <<< "$NAME" | sed -E 's/[-_.]+/-/g')"
    record uv.lock "$(table_get uv.lock '[[package]]' version "$LOCK_NAME")"
  fi
fi
if [ -f codemeta.json ]; then
  record codemeta.json "$(jq -r '.version // empty' codemeta.json)"
fi
if [ -f CITATION.cff ]; then
  record CITATION.cff "$(sed -nE "s/^version:[[:blank:]]*${QUOTED}[[:blank:]]*$/\1/p" CITATION.cff | head -1)"
fi

# The highest vX.Y.Z tag, if any.
LATEST_TAG=""
while IFS= read -r tag; do
  if [ -z "$LATEST_TAG" ] || newer "${tag#v}" "${LATEST_TAG#v}"; then LATEST_TAG="$tag"; fi
done < <(git tag -l 'v[0-9]*' 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)

if [ "${#FILES[@]}" -gt 0 ]; then
  CURRENT="${VERSIONS[0]}"
  for i in "${!FILES[@]}"; do
    if [ "${VERSIONS[$i]}" != "$CURRENT" ]; then
      say "these files disagree about the current version:"
      for j in "${!FILES[@]}"; do say "  ${VERSIONS[$j]}  ${FILES[$j]}"; done
      die "make them agree, then try again"
    fi
  done
  say "current version $CURRENT, from ${FILES[*]}"
elif [ -n "$LATEST_TAG" ]; then
  CURRENT="${LATEST_TAG#v}"
  say "no file carries a version; current version $CURRENT, from tag $LATEST_TAG"
else
  CURRENT="0.0.0"
  say "no file carries a version and there are no vX.Y.Z tags; starting from 0.0.0"
fi

# Work out and check the new version ─────────────────────────────────────────

IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$REQUEST" in
  major) VERSION="$((MAJOR + 1)).0.0" ;;
  minor) VERSION="$MAJOR.$((MINOR + 1)).0" ;;
  patch) VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  *)     VERSION="${REQUEST#v}"
         [[ "$VERSION" =~ $SEMVER ]] \
           || die "give major, minor, patch, or a version like 1.2.3, not \"$REQUEST\"" ;;
esac
TAG="v$VERSION"

newer "$VERSION" "$CURRENT" || die "$VERSION is not greater than the current version, $CURRENT"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists"
fi
if [ -n "$LATEST_TAG" ] && ! newer "$VERSION" "${LATEST_TAG#v}"; then
  die "$VERSION is not greater than the latest tag, $LATEST_TAG"
fi

grep -q '^## \[Unreleased\]' CHANGELOG.md \
  || die "CHANGELOG.md has no \"## [Unreleased]\" heading"
unreleased="$(awk '
  /^## \[Unreleased\]/     { inside = 1; next }
  inside && /^## \[/       { exit }
  inside && /^\[[^]]*\]: / { exit }
  inside                   { print }
' CHANGELOG.md)"
[ -n "$(tr -d '[:space:]' <<< "$unreleased")" ] \
  || die "the [Unreleased] section of CHANGELOG.md is empty, so there is nothing to release"

# Edit ───────────────────────────────────────────────────────────────────────

# Set key: VALUE in YAML, keeping the line’s quoting.
yaml_set() {
  awk -v key="$1" -v new="$2" '
    index($0, key ":") == 1 {
      if ($0 ~ /["'\'']/) sub(/["'\''][^"'\'']*["'\'']/, "\"" new "\"")
      else                sub(/:[ \t]*.*$/, ": " new)
    }
    { print }
  ' "$3"
}

for f in ${FILES[@]+"${FILES[@]}"}; do
  case "$f" in
    pyproject.toml) rewrite "$f" table_set '[project]' version '' "$VERSION" ;;
    setup.cfg)      rewrite "$f" table_set '[metadata]' version '' "$VERSION" ;;
    uv.lock)        rewrite "$f" table_set '[[package]]' version "$LOCK_NAME" "$VERSION" ;;
    codemeta.json)
      # Only top-level keys: programmingLanguage has a "version" of its own
      # further in. Edited line by line rather than rewritten by jq, so the
      # diff touches only the values that change. The top level’s indent is
      # the first key’s.
      indent="$(awk '/^[ \t]+"/ { match($0, /^[ \t]+/); print substr($0, 1, RLENGTH); exit }' codemeta.json)"
      # shellcheck disable=SC2016 # $0 is awk’s, not the shell’s.
      if jq -e 'has("datePublished")' codemeta.json >/dev/null; then
        rewrite "$f" awk -v i="$indent" -v version="$VERSION" -v date="$TODAY" '
          index($0, i "\"version\":") == 1       { sub(/: *"[^"]*"/, ": \"" version "\"") }
          index($0, i "\"datePublished\":") == 1 { sub(/: *"[^"]*"/, ": \"" date "\"") }
          { print }'
      else
        # shellcheck disable=SC2016 # $0 is awk’s, not the shell’s.
        rewrite "$f" awk -v i="$indent" -v version="$VERSION" -v date="$TODAY" '
          index($0, i "\"version\":") == 1 {
            print i "\"datePublished\": \"" date "\","
            sub(/: *"[^"]*"/, ": \"" version "\"")
          }
          { print }'
      fi
      ;;
    CITATION.cff)
      rewrite "$f" yaml_set version "$VERSION"
      if grep -q '^date-released:' CITATION.cff; then
        rewrite "$f" yaml_set date-released "$TODAY"
      fi
      ;;
    *) # __init__.py
      rewrite "$f" sed -E "s/^(__version__[[:blank:]]*=[[:blank:]]*[\"'])[^\"']*([\"'])/\1$VERSION\2/" ;;
  esac
done

# CHANGELOG.md: [Unreleased] becomes the version’s section, under a new empty
# [Unreleased]. With an "[Unreleased]: <repo>/compare/<tag>...HEAD" link, the
# version gets a compare link from the previous tag.
link="$(grep -E '^\[Unreleased\]: ' CHANGELOG.md || true)"
REPO_URL=""
PREV_TAG=""
if [[ "$link" =~ ^\[Unreleased\]:\ (.*)/compare/(.*)\.\.\.HEAD$ ]]; then
  REPO_URL="${BASH_REMATCH[1]}"
  PREV_TAG="${BASH_REMATCH[2]}"
elif [ -n "$link" ]; then
  say "leaving the [Unreleased] link alone: it isn't \"<repo>/compare/<tag>...HEAD\""
fi
rewrite CHANGELOG.md awk \
  -v version="$VERSION" -v date="$TODAY" \
  -v repo="$REPO_URL" -v prev="$PREV_TAG" -v tag="$TAG" '
  /^## \[Unreleased\]/ && !seen {
    print "## [Unreleased]"
    print ""
    print "## [" version "] - " date
    seen = 1
    next
  }
  /^\[Unreleased\]: / && repo != "" {
    print "[Unreleased]: " repo "/compare/" tag "...HEAD"
    print "[" version "]: " repo "/compare/" prev "..." tag
    next
  }
  { print }
'

# Check ──────────────────────────────────────────────────────────────────────

expect() { [ "$2" = "$VERSION" ] || die "could not set the version in $1 (it reads \"$2\")"; }
for f in ${FILES[@]+"${FILES[@]}"}; do
  s="$(staged "$f")"
  case "$f" in
    pyproject.toml) expect "$f" "$(table_get "$s" '[project]' version '')" ;;
    setup.cfg)      expect "$f" "$(table_get "$s" '[metadata]' version '')" ;;
    uv.lock)        expect "$f" "$(table_get "$s" '[[package]]' version "$LOCK_NAME")" ;;
    codemeta.json)  jq -e . "$s" >/dev/null 2>&1 || die "editing codemeta.json left invalid JSON"
                    expect "$f" "$(jq -r .version "$s")"
                    [ "$(jq -r .datePublished "$s")" = "$TODAY" ] \
                      || die "could not set datePublished in codemeta.json" ;;
    CITATION.cff)   expect "$f" "$(sed -nE "s/^version:[[:blank:]]*${QUOTED}[[:blank:]]*$/\1/p" "$s" | head -1)" ;;
    *)              expect "$f" "$(sed -nE "s/^__version__[[:blank:]]*=[[:blank:]]*${QUOTED}.*/\1/p" "$s" | head -1)" ;;
  esac
done
grep -qx "## \[$VERSION\] - $TODAY" "$(staged CHANGELOG.md)" \
  || die "could not add the $VERSION section to CHANGELOG.md"

# Write ──────────────────────────────────────────────────────────────────────

for f in CHANGELOG.md ${FILES[@]+"${FILES[@]}"}; do
  cat "$STAGE/$f" > "$f"
  say "updated $f"
done

if [ -n "$NOTES" ]; then
  # The section’s body, without its heading or surrounding blank lines.
  awk -v heading="## [$VERSION] - $TODAY" '
    $0 == heading            { inside = 1; next }
    inside && /^## \[/       { exit }
    inside && /^\[[^]]*\]: / { exit }
    inside                   { lines[++n] = $0 }
    END {
      first = 1; while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
      last = n;  while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = first; i <= last; i++) print lines[i]
    }
  ' CHANGELOG.md > "$NOTES"
  [ -s "$NOTES" ] || die "could not extract release notes from CHANGELOG.md"
fi

say "$CURRENT → $VERSION ($TODAY)"
echo "previous=$CURRENT"
echo "version=$VERSION"
echo "tag=$TAG"
