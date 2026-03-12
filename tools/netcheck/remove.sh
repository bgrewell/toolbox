#!/usr/bin/env bash
set -euo pipefail

INSTALL_PATH="/usr/local/bin/netcheck"

log() { printf '[*] %s\n' "$*"; }
die() { printf '[x] %s\n' "$*" >&2; exit 1; }

[[ $(id -u) -eq 0 ]] || die "This script must be run as root (try: sudo bash)"

if [[ -f "${INSTALL_PATH}" ]]; then
    rm "${INSTALL_PATH}"
    log "Removed ${INSTALL_PATH}"
else
    log "${INSTALL_PATH} not found, nothing to remove."
fi

log "Remove complete."
