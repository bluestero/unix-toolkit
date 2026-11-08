#!/usr/bin/env bash
# The kept tests: tests/run.sh [name...] (names: the files in tests/cases).
# With no name, every case but speed. Each test runs in a scratch HOME with fake
# system commands (tests/lib/fixture.py); install.sh never runs this.
set -uo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
if command -v uv >/dev/null; then
  exec uv run --quiet --no-project --with 'pyte==0.8.2' python "$here/lib/runner.py" "$@"
elif python3 -c 'import pyte' 2>/dev/null; then
  exec python3 "$here/lib/runner.py" "$@"
else
  echo "✗ the tests need uv (https://docs.astral.sh/uv/) or python3 with pyte (pip install pyte)" >&2
  exit 2
fi
