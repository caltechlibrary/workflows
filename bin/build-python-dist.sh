#!/usr/bin/env bash
#
# Check that a Python package's version numbers agree, then build its sdist and
# wheel and check them with twine.
#
#   build-python-dist.sh --project-dir . --tag v1.2.3
#
# The version that gets published is the one in pyproject.toml's [project]
# table, or in setup.cfg's [metadata] section if pyproject.toml has none. The
# build fails if any of these that exist disagree with it:
#
#   <package>/__init__.py or src/<package>/__init__.py   __version__
#   codemeta.json                                       "version"
#   CITATION.cff                                        version:
#   setup.cfg, when the version came from pyproject.toml
#   the release tag, when --tag is given                v<version> or <version>
#
# A file that is absent, or has no literal version in it, is reported and
# skipped rather than failing the build.
#
# This installs nothing. It needs `build` and `twine` importable by the Python
# it runs; the build-python-dist action installs pinned versions of both.

set -euo pipefail

PROJECT_DIR="."
OUTPUT=""
TAG=""
INIT_FILE=""
PYTHON="${PYTHON:-python3}"

usage() {
  cat <<'USAGE'
build-python-dist.sh -- check version consistency, build, and twine-check a package

Options:
  --project-dir DIR   directory holding pyproject.toml or setup.cfg  (default: .)
  --output DIR        where the sdist and wheel go     (default: <project-dir>/dist)
  --tag NAME          release tag the version must match, e.g. v1.2.3
  --init-file PATH    file holding __version__, relative to the project
                      (default: found from the package name)
  -h, --help          this text

Environment:
  PYTHON              interpreter to use                   (default: python3)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)  PROJECT_DIR="$2"; shift 2 ;;
    --output)       OUTPUT="$2"; shift 2 ;;
    --tag)          TAG="$2"; shift 2 ;;
    --init-file)    INIT_FILE="$2"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "build-python-dist: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$OUTPUT" ] || OUTPUT="$PROJECT_DIR/dist"

command -v "$PYTHON" >/dev/null || {
  echo "build-python-dist: $PYTHON is not installed" >&2; exit 1; }
for mod in build twine; do
  "$PYTHON" -c "import $mod" 2>/dev/null || {
    echo "build-python-dist: the $mod module is not installed for $PYTHON" >&2
    echo "  $PYTHON -m pip install build twine" >&2
    exit 1
  }
done
[ -f "$PROJECT_DIR/pyproject.toml" ] || [ -f "$PROJECT_DIR/setup.cfg" ] || {
  echo "build-python-dist: no pyproject.toml or setup.cfg in $PROJECT_DIR" >&2
  exit 1
}

# Prints the version on stdout; reports and errors go to stderr.
VERSION="$(TAG="${TAG#refs/tags/}" INIT_FILE="$INIT_FILE" \
             "$PYTHON" - "$PROJECT_DIR" <<'PY'
import configparser, json, os, re, sys

root = sys.argv[1]
tag = os.environ['TAG']
init_file = os.environ['INIT_FILE']

def path(name):
    return os.path.join(root, name)

def read(name):
    with open(path(name), encoding='utf-8') as f:
        return f.read()

def say(message):
    print(f'build-python-dist: {message}', file=sys.stderr)

def literal(value):
    # setuptools accepts "attr: pkg.__version__" and "file: VERSION" in
    # setup.cfg; those are directives, not version numbers.
    value = (value or '').strip()
    return value if value and not re.match(r'^(attr|file):', value) else None

project = {}
if os.path.exists(path('pyproject.toml')):
    try:
        import tomllib
    except ImportError:
        say('reading pyproject.toml needs Python 3.11 or later')
        sys.exit(1)
    with open(path('pyproject.toml'), 'rb') as f:
        project = tomllib.load(f).get('project', {})

metadata = {}
if os.path.exists(path('setup.cfg')):
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(path('setup.cfg'), encoding='utf-8')
    if cfg.has_section('metadata'):
        metadata = dict(cfg['metadata'])

if literal(project.get('version')):
    version, source = project['version'].strip(), 'pyproject.toml'
elif literal(metadata.get('version')):
    version, source = metadata['version'].strip(), 'setup.cfg'
else:
    say('no literal version in pyproject.toml [project] or setup.cfg [metadata]')
    say('a dynamic version cannot be checked for consistency before building')
    sys.exit(1)
say(f'version {version} from {source}')

found = {}   # file -> version it holds
skipped = [] # (file, why)

if source == 'pyproject.toml' and 'version' in metadata:
    if literal(metadata['version']):
        found['setup.cfg'] = metadata['version'].strip()
    else:
        skipped.append(('setup.cfg', 'version is not a literal'))

if not init_file:
    name = project.get('name') or metadata.get('name') or ''
    package = re.sub(r'[-.]+', '_', name.strip()).lower()
    candidates = [f'{package}/__init__.py', f'src/{package}/__init__.py']
    init_file = next((c for c in candidates if package and os.path.exists(path(c))), '')
    if not init_file:
        skipped.append((' or '.join(candidates) if package else '__init__.py',
                        'not found'))
if init_file:
    if not os.path.exists(path(init_file)):
        say(f'no such file: {init_file}')
        sys.exit(1)
    m = re.search(r'''^__version__\s*(?::\s*str\s*)?=\s*['"]([^'"]+)['"]''',
                  read(init_file), re.M)
    if m:
        found[init_file] = m.group(1)
    else:
        skipped.append((init_file, 'no literal __version__'))

if os.path.exists(path('codemeta.json')):
    text = read('codemeta.json')
    try:
        data = json.loads(text)
    except ValueError:
        # Some codemeta.json files in the wild carry trailing commas.
        data = json.loads(re.sub(r',(\s*[}\]])', r'\1', text))
    if isinstance(data, dict) and data.get('version'):
        found['codemeta.json'] = str(data['version'])
    else:
        skipped.append(('codemeta.json', 'no version field'))
else:
    skipped.append(('codemeta.json', 'not found'))

if os.path.exists(path('CITATION.cff')):
    m = re.search(r'''^version:\s*['"]?([^'"\s#]+)''', read('CITATION.cff'), re.M)
    if m:
        found['CITATION.cff'] = m.group(1)
    else:
        skipped.append(('CITATION.cff', 'no version field'))
else:
    skipped.append(('CITATION.cff', 'not found'))

errors = []
for file, value in found.items():
    if value == version:
        say(f'  {file}: {value}')
    else:
        errors.append(f'{file} has version {value}, but {source} has {version}')
for file, why in skipped:
    say(f'  {file}: not checked ({why})')

if tag:
    if tag in (f'v{version}', version):
        say(f'  release tag: {tag}')
    else:
        errors.append(f'release tag {tag} does not match v{version}')
else:
    say('  release tag: not checked (no --tag)')

for message in errors:
    say(f'error: {message}')
if errors:
    sys.exit(1)
print(version)
PY
)"

# Stale files from an earlier build would otherwise be uploaded alongside the
# new ones. Only distribution files are removed; anything else is left alone.
mkdir -p "$OUTPUT"
find "$OUTPUT" -maxdepth 1 -type f \( -name '*.whl' -o -name '*.tar.gz' \) -delete

echo "$PYTHON -m build --outdir $OUTPUT $PROJECT_DIR"
"$PYTHON" -m build --outdir "$OUTPUT" "$PROJECT_DIR"

declare -a FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  find "$OUTPUT" -maxdepth 1 -type f \( -name '*.whl' -o -name '*.tar.gz' \) | sort)
[ "${#FILES[@]}" -gt 0 ] || {
  echo "build-python-dist: $OUTPUT contains no sdist or wheel" >&2; exit 1; }

"$PYTHON" -m twine check --strict "${FILES[@]}"

# The checks above read the source; this reads what was actually built, which
# catches a build backend that took its version from somewhere else.
"$PYTHON" - "$VERSION" "${FILES[@]}" <<'PY'
import os, sys
from packaging.utils import parse_sdist_filename, parse_wheel_filename
from packaging.version import Version

expected = Version(sys.argv[1])
bad = []
for f in sys.argv[2:]:
    name = os.path.basename(f)
    parse = parse_wheel_filename if name.endswith('.whl') else parse_sdist_filename
    if parse(name)[1] != expected:
        bad.append(name)
for name in bad:
    print(f'build-python-dist: {name} was built with a version other than {expected}',
          file=sys.stderr)
sys.exit(1 if bad else 0)
PY

echo "build-python-dist: $VERSION, ${#FILES[@]} file(s) into $OUTPUT"
for f in "${FILES[@]}"; do echo "  $(basename "$f")"; done
