#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-./config.env}"

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "error: config file not found: $CONFIG_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${CHAIN_NAME:=REDSOCKS}"
: "${REDSOCKS_CONF:=/etc/redsocks.conf}"

echo "=== redsocks service ==="
systemctl --no-pager --full status redsocks-transparent.service || true
echo

echo "=== listening sockets ==="
ss -lntp | grep -E "redsocks|:${REDSOCKS_LOCAL_PORT}\b" || true
echo

echo "=== iptables nat rules ==="
iptables -t nat -S || true
echo

echo "=== chain ${CHAIN_NAME} ==="
iptables -t nat -S "$CHAIN_NAME" 2>/dev/null || echo "chain not present"
echo

echo "=== redsocks config ==="
if [[ -f "$REDSOCKS_CONF" ]]; then
  cat "$REDSOCKS_CONF"
else
  echo "config not found: $REDSOCKS_CONF"
fi
