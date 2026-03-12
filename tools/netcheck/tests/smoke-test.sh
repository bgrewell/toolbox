#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '[x] %s\n' "$*" >&2
  exit 1
}

pass() {
  printf '[*] %s\n' "$*"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for file in \
  "$ROOT_DIR/README.md" \
  "$ROOT_DIR/netcheck.py" \
  "$ROOT_DIR/install.sh" \
  "$ROOT_DIR/remove.sh"
do
  [[ -f "$file" ]] || fail "missing required file: $file"
done

bash -n "$ROOT_DIR/install.sh" || fail "syntax error in install.sh"
bash -n "$ROOT_DIR/remove.sh"  || fail "syntax error in remove.sh"

python3 -m py_compile "$ROOT_DIR/netcheck.py" || fail "syntax error in netcheck.py"

python3 "$ROOT_DIR/netcheck.py" --version > /dev/null || fail "--version flag failed"

pass "smoke test passed"
