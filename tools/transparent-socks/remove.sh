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
: "${SYSTEMD_UNIT_DEST:=/etc/systemd/system/redsocks-transparent.service}"
: "${IPTABLES_SAVE_FILE:=/etc/iptables/rules.v4}"

log() {
  printf '[*] %s\n' "$*"
}

remove_chain() {
  iptables -t nat -D OUTPUT -p tcp -j "$CHAIN_NAME" 2>/dev/null || true
  iptables -t nat -F "$CHAIN_NAME" 2>/dev/null || true
  iptables -t nat -X "$CHAIN_NAME" 2>/dev/null || true
}

stop_disable_service() {
  systemctl stop redsocks-transparent.service 2>/dev/null || true
  systemctl disable redsocks-transparent.service 2>/dev/null || true
}

remove_unit() {
  if [[ -f "$SYSTEMD_UNIT_DEST" ]]; then
    rm -f "$SYSTEMD_UNIT_DEST"
    systemctl daemon-reload
  fi
}

persist_iptables() {
  mkdir -p "$(dirname "$IPTABLES_SAVE_FILE")"
  iptables-save > "$IPTABLES_SAVE_FILE" || true
}

main() {
  remove_chain
  persist_iptables
  stop_disable_service
  remove_unit

  log "transparent socks configuration removed"
  log "note: redsocks package was left installed"
  log "note: config file was left at $REDSOCKS_CONF"
}

main "$@"
