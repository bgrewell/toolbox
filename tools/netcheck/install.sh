#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/bgrewell/toolbox/main"
INSTALL_PATH="/usr/local/bin/netcheck"

log() { printf '[*] %s\n' "$*"; }
die() { printf '[x] %s\n' "$*" >&2; exit 1; }

[[ $(id -u) -eq 0 ]] || die "This script must be run as root (try: sudo bash)"

log "Downloading netcheck to ${INSTALL_PATH} ..."
curl -fsSL "${REPO_RAW}/tools/netcheck/netcheck.py" -o "${INSTALL_PATH}"

chmod +x "${INSTALL_PATH}"
log "Set executable permissions on ${INSTALL_PATH}"

log "Verifying installation ..."
"${INSTALL_PATH}" --version

log "Install complete."
