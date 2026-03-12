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
  "$ROOT_DIR/config.env.example" \
  "$ROOT_DIR/setup.sh" \
  "$ROOT_DIR/remove.sh" \
  "$ROOT_DIR/status.sh" \
  "$ROOT_DIR/files/redsocks.conf.template" \
  "$ROOT_DIR/systemd/redsocks-transparent.service"
do
  [[ -f "$file" ]] || fail "missing required file: $file"
done

bash -n "$ROOT_DIR/setup.sh"
bash -n "$ROOT_DIR/remove.sh"
bash -n "$ROOT_DIR/status.sh"

grep -q "__PROXY_HOST__" "$ROOT_DIR/files/redsocks.conf.template" \
  || fail "template placeholder missing: __PROXY_HOST__"

grep -q "ExecStart=/usr/bin/redsocks -c /etc/redsocks.conf" \
  "$ROOT_DIR/systemd/redsocks-transparent.service" \
  || fail "systemd unit missing expected ExecStart"

pass "smoke test passed"
