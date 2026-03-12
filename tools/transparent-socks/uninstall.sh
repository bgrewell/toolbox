#!/usr/bin/env bash
set -euo pipefail

# Transparent SOCKS proxy uninstaller
# Usage: curl -fsSL <url>/uninstall.sh | sudo bash -s -- [options]

# ── Defaults ─────────────────────────────────────────────────────────────────
CHAIN_NAME="REDSOCKS"
REDSOCKS_CONF="/etc/redsocks.conf"
SYSTEMD_UNIT_DEST="/etc/systemd/system/redsocks-transparent.service"
IPTABLES_SAVE_FILE="/etc/iptables/rules.v4"

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { printf '[*] %s\n' "$*"; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: uninstall.sh [OPTIONS]

Optional:
  --chain NAME         iptables NAT chain name  (default: REDSOCKS)
  --purge              Also remove redsocks config file
  -h, --help           Show this help

All options have sensible defaults matching install.sh.
USAGE
  exit 0
}

# ── Argument parsing ─────────────────────────────────────────────────────────
PURGE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chain)   CHAIN_NAME="$2"; shift 2 ;;
    --purge)   PURGE=true;      shift ;;
    -h|--help) usage ;;
    *)         die "unknown option: $1" ;;
  esac
done

# ── Validation ───────────────────────────────────────────────────────────────
[[ $(id -u) -eq 0 ]] || die "This script must be run as root (try: sudo bash)"

# ── Remove iptables chain ────────────────────────────────────────────────────
log "Removing iptables chain: ${CHAIN_NAME}"
iptables -t nat -D OUTPUT -p tcp -j "$CHAIN_NAME" 2>/dev/null || true
iptables -t nat -F "$CHAIN_NAME" 2>/dev/null || true
iptables -t nat -X "$CHAIN_NAME" 2>/dev/null || true

# Persist cleaned rules
mkdir -p "$(dirname "$IPTABLES_SAVE_FILE")"
iptables-save > "$IPTABLES_SAVE_FILE" 2>/dev/null || true

# ── Stop and remove systemd service ──────────────────────────────────────────
log "Stopping redsocks service"
systemctl stop redsocks-transparent.service 2>/dev/null || true
systemctl disable redsocks-transparent.service 2>/dev/null || true

if [[ -f "$SYSTEMD_UNIT_DEST" ]]; then
  rm -f "$SYSTEMD_UNIT_DEST"
  systemctl daemon-reload
  log "Removed ${SYSTEMD_UNIT_DEST}"
fi

# ── Optional config cleanup ──────────────────────────────────────────────────
if [[ "$PURGE" == true ]]; then
  if [[ -f "$REDSOCKS_CONF" ]]; then
    rm -f "$REDSOCKS_CONF"
    log "Removed ${REDSOCKS_CONF}"
  fi
else
  log "Note: redsocks config left at ${REDSOCKS_CONF} (use --purge to remove)"
fi

log "Note: redsocks package was left installed (apt remove redsocks to uninstall)"
log "Uninstall complete."
