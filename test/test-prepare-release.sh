#!/usr/bin/env bash
#
# Exercise bin/prepare-release.sh against copies of test/fixture-release.
# CI runs this; so can you, from the repository root:
#
#   test/test-prepare-release.sh
#
# Set BASH_UNDER_TEST to run the script with a particular bash, such as the
# 3.2 that macOS ships: BASH_UNDER_TEST=/bin/bash test/test-prepare-release.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/bin/prepare-release.sh"
FIXTURE="$ROOT/test/fixture-release"
BASH_UNDER_TEST="${BASH_UNDER_TEST:-bash}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }
pass() { echo "ok: $*"; }

# A fresh copy of the fixture as a git repository tagged v1.4.2; prints its path.
fresh() {
  local dir="$WORK/$1"
  rm -rf "$dir"
  cp -R "$FIXTURE" "$dir"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.name=test -c user.email=test@example.com commit -qm fixture
  git -C "$dir" tag v1.4.2
  echo "$dir"
}

run() { "$BASH_UNDER_TEST" "$SCRIPT" --date 2026-11-20 "$@"; }

# Succeeds if the script fails, leaves the tree untouched, and says $2.
refuses() {
  local dir="$1" message="$2"; shift 2
  if run --project-dir "$dir" "$@" >/dev/null 2>"$WORK/err"; then
    fail "should have refused: $*"; return
  fi
  grep -qF "$message" "$WORK/err" || fail "unhelpful error for $*: $(cat "$WORK/err")"
  [ -z "$(git -C "$dir" status --porcelain)" ] || fail "refusing $* still changed files"
}

# A minor release updates every file ─────────────────────────────────────────

d="$(fresh minor)"
out="$(run --project-dir "$d" --notes "$WORK/notes.md" minor 2>"$WORK/log")" \
  || { cat "$WORK/log" >&2; fail "minor release failed"; }

[ "$out" = "$(printf 'previous=1.4.2\nversion=1.5.0\ntag=v1.5.0')" ] \
  || fail "unexpected stdout: $out"
grep -qx 'version = "1.5.0"' "$d/pyproject.toml" || fail "pyproject.toml not updated"
grep -qx 'version = "9.9.9"' "$d/pyproject.toml" || fail "another table's version was changed"
[ "$(awk '/^name = "fixture-release"/{getline; print}' "$d/uv.lock")" = 'version = "1.5.0"' ] \
  || fail "uv.lock's project version not updated"
[ "$(awk '/^name = "requests"/{getline; print}' "$d/uv.lock")" = 'version = "1.4.2"' ] \
  || fail "a dependency's version in uv.lock was changed"
grep -q '^version = 1$' "$d/uv.lock" || fail "uv.lock's own format version was changed"
grep -qx "__version__ = '1.5.0'" "$d/src/fixture_release/__init__.py" \
  || fail "__version__ not updated, or its quotes changed"
[ "$(jq -r .version "$d/codemeta.json")" = 1.5.0 ] || fail "codemeta.json version not updated"
[ "$(jq -r .datePublished "$d/codemeta.json")" = 2026-11-20 ] || fail "datePublished not added"
[ "$(jq -r .programmingLanguage.version "$d/codemeta.json")" = 3.13 ] \
  || fail "codemeta.json's programmingLanguage version was changed"
grep -qx 'version: 1.5.0' "$d/CITATION.cff" || fail "CITATION.cff version not updated, or quoted"
grep -qx 'date-released: "2026-11-20"' "$d/CITATION.cff" || fail "date-released not updated"

expected_changelog="$(cat <<'EOF'
# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.5.0] - 2026-11-20

### Added

- a thing worth releasing

## [1.4.2] - 2026-01-15

### Fixed

- an older fix

[Unreleased]: https://github.com/example/fixture-release/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/example/fixture-release/compare/v1.4.2...v1.5.0
[1.4.2]: https://github.com/example/fixture-release/compare/v1.4.1...v1.4.2
EOF
)"
[ "$(cat "$d/CHANGELOG.md")" = "$expected_changelog" ] \
  || { fail "CHANGELOG.md is not as expected"; diff <(echo "$expected_changelog") "$d/CHANGELOG.md" >&2 || true; }
[ "$(cat "$WORK/notes.md")" = "$(printf '### Added\n\n- a thing worth releasing')" ] \
  || fail "notes are not the section body: $(cat "$WORK/notes.md")"
changed="$(git -C "$d" status --porcelain | awk '{print $2}' | sort | tr '\n' ' ')"
[ "$changed" = "CHANGELOG.md CITATION.cff codemeta.json pyproject.toml src/fixture_release/__init__.py uv.lock " ] \
  || fail "unexpected set of changed files: $changed"
[ "$FAILED" -eq 0 ] && pass "minor release updates every file"

# Bump levels and explicit versions ──────────────────────────────────────────

for case in "major 2.0.0" "patch 1.4.3" "1.6.0 1.6.0" "v1.6.0 1.6.0"; do
  read -r request expected <<< "$case"
  d="$(fresh "bump-$request")"
  got="$(run --project-dir "$d" "$request" 2>/dev/null | sed -n 's/^version=//p')"
  if [ "$got" = "$expected" ]; then pass "$request gives $expected"
  else fail "$request gave \"$got\", not $expected"; fi
done

# A second release, with datePublished now present, updates it ──────────────

d="$(fresh twice)"
run --project-dir "$d" minor >/dev/null 2>&1
printf '%s\n' '/^## \[Unreleased\]/a' '' '- another' '.' 'w' 'q' | ed -s "$d/CHANGELOG.md"
"$BASH_UNDER_TEST" "$SCRIPT" --project-dir "$d" --date 2026-12-01 patch >/dev/null 2>&1 \
  || fail "second release failed"
[ "$(jq -r .datePublished "$d/codemeta.json")" = 2026-12-01 ] || fail "datePublished not updated"
[ "$(grep -c datePublished "$d/codemeta.json")" -eq 1 ] || fail "datePublished added twice"
[ "$(jq -r .version "$d/codemeta.json")" = 1.5.1 ] || fail "second release has the wrong version"
pass "a second release updates datePublished in place"

# Refusals leave every file as it was ───────────────────────────────────────

d="$(fresh refusals)"
refuses "$d" "is not greater than the current version, 1.4.2" 1.4.2
refuses "$d" "is not greater than the current version, 1.4.2" 1.0.0
refuses "$d" "give major, minor, patch, or a version like 1.2.3" next
refuses "$d" "give major, minor, patch, or a version like 1.2.3" 1.5
git -C "$d" tag v1.5.0
refuses "$d" "tag v1.5.0 already exists" minor
git -C "$d" tag -d v1.5.0 >/dev/null
git -C "$d" tag v1.9.0
refuses "$d" "is not greater than the latest tag, v1.9.0" minor
pass "bad requests are refused"

d="$(fresh disagree)"
sed -i.bak 's/^version: 1.4.2/version: 1.4.1/' "$d/CITATION.cff" && rm "$d/CITATION.cff.bak"
git -C "$d" -c user.name=test -c user.email=test@example.com commit -qam disagree
refuses "$d" "these files disagree about the current version" minor
grep -qF "1.4.1  CITATION.cff" "$WORK/err" || fail "the disagreeing file is not named"
pass "disagreeing files are refused, and named"

d="$(fresh empty)"
awk '/^## \[Unreleased\]/{print; skip=1; next} /^## \[1.4.2\]/{skip=0; print ""} !skip' \
  "$FIXTURE/CHANGELOG.md" > "$d/CHANGELOG.md"
git -C "$d" -c user.name=test -c user.email=test@example.com commit -qam empty
refuses "$d" "the [Unreleased] section of CHANGELOG.md is empty" minor
pass "an empty [Unreleased] is refused"

d="$(fresh no-changelog)"
git -C "$d" rm -q CHANGELOG.md
git -C "$d" -c user.name=test -c user.email=test@example.com commit -qm no-changelog
refuses "$d" "no CHANGELOG.md" minor
pass "a missing CHANGELOG.md is refused"

# Other project shapes ───────────────────────────────────────────────────────

# No compare links: the section is still made, and nothing else changes.
d="$(fresh no-links)"
grep -v '^\[' "$FIXTURE/CHANGELOG.md" > "$d/CHANGELOG.md"
git -C "$d" -c user.name=test -c user.email=test@example.com commit -qam no-links
run --project-dir "$d" minor >/dev/null 2>&1 || fail "release without compare links failed"
grep -qx '## \[1.5.0\] - 2026-11-20' "$d/CHANGELOG.md" || fail "no section without compare links"
grep -q '^\[' "$d/CHANGELOG.md" && fail "links were added where there were none"
pass "a changelog without compare links still gets its section"

# Only a changelog and codemeta.json, as in a repository that isn’t a package.
d="$(fresh codemeta-only)"
git -C "$d" rm -q -r pyproject.toml uv.lock src CITATION.cff
git -C "$d" -c user.name=test -c user.email=test@example.com commit -qm codemeta-only
run --project-dir "$d" patch >/dev/null 2>&1 || fail "codemeta-only release failed"
[ "$(jq -r .version "$d/codemeta.json")" = 1.4.3 ] || fail "codemeta-only release did not bump"
pass "a project with only codemeta.json works"

# No file carries a version: the latest tag is the current version.
d="$(fresh tags-only)"
git -C "$d" rm -q -r pyproject.toml uv.lock src CITATION.cff codemeta.json
git -C "$d" -c user.name=test -c user.email=test@example.com commit -qm tags-only
got="$(run --project-dir "$d" minor 2>/dev/null | sed -n 's/^version=//p')"
[ "$got" = 1.5.0 ] || fail "tags-only release gave \"$got\", not 1.5.0"
pass "with no versioned files, the latest tag is the current version"

# setup.cfg, with a bare value, and a dynamic version in pyproject.toml.
d="$(fresh setupcfg)"
sed -i.bak 's/^version = "1.4.2"$/dynamic = ["version"]/' "$d/pyproject.toml" && rm "$d/pyproject.toml.bak"
printf '[metadata]\nname = Fixture.Release\nversion = 1.4.2\n' > "$d/setup.cfg"
git -C "$d" add -A
git -C "$d" -c user.name=test -c user.email=test@example.com commit -qm setupcfg
run --project-dir "$d" minor >/dev/null 2>"$WORK/log" || { cat "$WORK/log" >&2; fail "setup.cfg release failed"; }
grep -qx 'version = 1.5.0' "$d/setup.cfg" || fail "setup.cfg not updated, or quoted"
grep -q '^dynamic = \["version"\]$' "$d/pyproject.toml" || fail "a dynamic version was touched"
pass "setup.cfg is updated and a dynamic version is left alone"

[ "$FAILED" -eq 0 ] || { echo "some checks failed" >&2; exit 1; }
# shellcheck disable=SC2016 # $BASH_VERSION is the tested bash’s, not ours.
echo "all prepare-release checks passed ($("$BASH_UNDER_TEST" -c 'echo bash $BASH_VERSION'))"
