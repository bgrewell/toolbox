#!/usr/bin/env bash
set -euo pipefail

# Transparent SOCKS proxy installer
# Usage: curl -fsSL <url>/install.sh | sudo bash -s -- --proxy <host> [options]

# ── Defaults ─────────────────────────────────────────────────────────────────
PROXY_TYPE="socks5"
PROXY_HOST=""
PROXY_PORT="1080"
PROXY_USER=""
PROXY_PASS=""
REDSOCKS_LOCAL_IP="127.0.0.1"
REDSOCKS_LOCAL_PORT="18086"
CHAIN_NAME="REDSOCKS"
BYPASS_UID=""
EXTRA_BYPASS_CIDRS=""
EXTRA_BYPASS_PORTS="22"
REDSOCKS_CONF="/etc/redsocks.conf"
SYSTEMD_UNIT_DEST="/etc/systemd/system/redsocks-transparent.service"
IPTABLES_SAVE_FILE="/etc/iptables/rules.v4"

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: install.sh [OPTIONS]

Required:
  --proxy HOST             Upstream proxy host (IP or hostname)

Optional:
  --proxy-port PORT        Upstream proxy port              (default: 1080)
  --proxy-type TYPE        socks4, socks5, or http-connect  (default: socks5)
  --proxy-user USER        Proxy username
  --proxy-pass PASS        Proxy password
  --redsocks-ip IP         Local redsocks listen IP         (default: 127.0.0.1)
  --redsocks-port PORT     Local redsocks listen port       (default: 18086)
  --chain NAME             iptables NAT chain name          (default: REDSOCKS)
  --bypass-uid UID         UID whose traffic bypasses proxy
  --bypass-cidrs "CIDRS"   Space-separated CIDRs to bypass
  --bypass-ports "PORTS"   Space-separated ports to bypass  (default: 22)
  -h, --help               Show this help
USAGE
  exit 0
}

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proxy)          PROXY_HOST="$2";          shift 2 ;;
    --proxy-port)     PROXY_PORT="$2";          shift 2 ;;
    --proxy-type)     PROXY_TYPE="$2";          shift 2 ;;
    --proxy-user)     PROXY_USER="$2";          shift 2 ;;
    --proxy-pass)     PROXY_PASS="$2";          shift 2 ;;
    --redsocks-ip)    REDSOCKS_LOCAL_IP="$2";   shift 2 ;;
    --redsocks-port)  REDSOCKS_LOCAL_PORT="$2"; shift 2 ;;
    --chain)          CHAIN_NAME="$2";          shift 2 ;;
    --bypass-uid)     BYPASS_UID="$2";          shift 2 ;;
    --bypass-cidrs)   EXTRA_BYPASS_CIDRS="$2";  shift 2 ;;
    --bypass-ports)   EXTRA_BYPASS_PORTS="$2";  shift 2 ;;
    -h|--help)        usage ;;
    *)                die "unknown option: $1" ;;
  esac
done

# ── Validation ───────────────────────────────────────────────────────────────
[[ $(id -u) -eq 0 ]] || die "This script must be run as root (try: sudo bash)"
[[ -n "$PROXY_HOST" ]] || die "Missing required --proxy HOST"

case "$PROXY_TYPE" in
  socks4|socks5|http-connect) ;;
  *) die "Unsupported --proxy-type: $PROXY_TYPE (use socks4, socks5, or http-connect)" ;;
esac

if [[ -n "$PROXY_USER" && -z "$PROXY_PASS" ]] || [[ -z "$PROXY_USER" && -n "$PROXY_PASS" ]]; then
  die "--proxy-user and --proxy-pass must be set together"
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_cmd apt-get
require_cmd dpkg
require_cmd iptables
require_cmd iptables-save
require_cmd getent
require_cmd systemctl

# ── Preflight checks ────────────────────────────────────────────────────────
log "Running preflight checks ..."

# Validate port numbers are numeric and in range
validate_port() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || die "${name} must be a number, got: ${value}"
  ((value >= 1 && value <= 65535))  || die "${name} must be 1-65535, got: ${value}"
}
validate_port "--proxy-port" "$PROXY_PORT"
validate_port "--redsocks-port" "$REDSOCKS_LOCAL_PORT"

# Check that the redsocks local port is not already in use
if ss -tlnp 2>/dev/null | grep -q ":${REDSOCKS_LOCAL_PORT} "; then
  existing=$(ss -tlnp 2>/dev/null | grep ":${REDSOCKS_LOCAL_PORT} " | head -1)
  die "Port ${REDSOCKS_LOCAL_PORT} is already in use: ${existing}"
fi

# Resolve proxy host to verify DNS works and host is reachable
resolve_ipv4s() {
  local host="$1"
  if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%s\n' "$host"
    return 0
  fi
  getent ahostsv4 "$host" | awk '{print $1}' | sort -u
}

proxy_ips=()
mapfile -t proxy_ips < <(resolve_ipv4s "$PROXY_HOST")
if ((${#proxy_ips[@]} == 0)); then
  die "Cannot resolve proxy host '${PROXY_HOST}' to an IPv4 address"
fi
log "  Proxy host resolves to: ${proxy_ips[*]}"

# Test TCP connectivity to the proxy
probe_ip="${proxy_ips[0]}"
if command -v nc >/dev/null 2>&1; then
  if ! nc -z -w 5 "$probe_ip" "$PROXY_PORT" 2>/dev/null; then
    die "Cannot connect to proxy at ${probe_ip}:${PROXY_PORT} (TCP connection refused or timed out)"
  fi
  log "  TCP connection to ${probe_ip}:${PROXY_PORT} succeeded"
elif command -v bash >/dev/null 2>&1; then
  if ! (echo >/dev/tcp/"$probe_ip"/"$PROXY_PORT") 2>/dev/null; then
    die "Cannot connect to proxy at ${probe_ip}:${PROXY_PORT} (TCP connection refused or timed out)"
  fi
  log "  TCP connection to ${probe_ip}:${PROXY_PORT} succeeded"
else
  warn "Neither nc nor /dev/tcp available — skipping proxy connectivity check"
fi

# Check for existing iptables chain that might conflict
if iptables -t nat -S "$CHAIN_NAME" >/dev/null 2>&1; then
  warn "iptables chain '${CHAIN_NAME}' already exists — it will be replaced"
fi

# Warn if redsocks service is already running
if systemctl is-active --quiet redsocks-transparent.service 2>/dev/null; then
  warn "redsocks-transparent.service is already running — it will be restarted"
fi

log "  Preflight checks passed"

# ── Package installation ─────────────────────────────────────────────────────
apt_install_if_missing() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    log "Installing package: $pkg"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"
  fi
}

apt_install_if_missing redsocks
apt_install_if_missing iptables
apt_install_if_missing iptables-persistent

# ── Generate redsocks config ─────────────────────────────────────────────────
auth_block=""
if [[ -n "$PROXY_USER" ]]; then
  auth_block=$(printf '  login = "%s";\n  password = "%s";' "$PROXY_USER" "$PROXY_PASS")
fi

log "Writing redsocks config to ${REDSOCKS_CONF}"
mkdir -p "$(dirname "$REDSOCKS_CONF")"
cat > "$REDSOCKS_CONF" <<CONF
base {
  log_debug = off;
  log_info = on;
  log = "syslog:daemon";
  daemon = on;
  redirector = iptables;
}

redsocks {
  local_ip = ${REDSOCKS_LOCAL_IP};
  local_port = ${REDSOCKS_LOCAL_PORT};
  ip = ${PROXY_HOST};
  port = ${PROXY_PORT};
  type = ${PROXY_TYPE};
${auth_block}
}
CONF

# ── Install systemd unit ─────────────────────────────────────────────────────
log "Installing systemd unit to ${SYSTEMD_UNIT_DEST}"
mkdir -p "$(dirname "$SYSTEMD_UNIT_DEST")"
cat > "$SYSTEMD_UNIT_DEST" <<'UNIT'
[Unit]
Description=Transparent redsocks proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/sbin/redsocks -c /etc/redsocks.conf
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable redsocks-transparent.service

# ── Start redsocks ────────────────────────────────────────────────────────────
log "Starting redsocks"
systemctl restart redsocks-transparent.service
systemctl --no-pager --full status redsocks-transparent.service || true

# ── iptables setup ────────────────────────────────────────────────────────────
log "Rebuilding iptables chain: ${CHAIN_NAME}"

# Remove existing chain if present
iptables -t nat -D OUTPUT -p tcp -j "$CHAIN_NAME" 2>/dev/null || true
iptables -t nat -F "$CHAIN_NAME" 2>/dev/null || true
iptables -t nat -X "$CHAIN_NAME" 2>/dev/null || true

iptables -t nat -N "$CHAIN_NAME"

# Reserved/local/private ranges
for cidr in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
  iptables -t nat -A "$CHAIN_NAME" -d "$cidr" -j RETURN
done

# Bypass the upstream proxy itself (proxy_ips populated during preflight)
for ip in "${proxy_ips[@]}"; do
  iptables -t nat -A "$CHAIN_NAME" -d "${ip}/32" -j RETURN
done

# Avoid redirect loop into local redsocks port
iptables -t nat -A "$CHAIN_NAME" -p tcp --dport "$REDSOCKS_LOCAL_PORT" -j RETURN

# Optional bypasses
for port in ${EXTRA_BYPASS_PORTS:-}; do
  iptables -t nat -A "$CHAIN_NAME" -p tcp --dport "$port" -j RETURN
done

for cidr in ${EXTRA_BYPASS_CIDRS:-}; do
  iptables -t nat -A "$CHAIN_NAME" -d "$cidr" -j RETURN
done

if [[ -n "${BYPASS_UID}" ]]; then
  iptables -t nat -A "$CHAIN_NAME" -m owner --uid-owner "$BYPASS_UID" -j RETURN
fi

# Redirect remaining outbound TCP into redsocks
iptables -t nat -A "$CHAIN_NAME" -p tcp -j REDIRECT --to-ports "$REDSOCKS_LOCAL_PORT"
iptables -t nat -A OUTPUT -p tcp -j "$CHAIN_NAME"

# Persist rules
mkdir -p "$(dirname "$IPTABLES_SAVE_FILE")"
iptables-save > "$IPTABLES_SAVE_FILE"

log "Setup complete"
log "  Upstream proxy: ${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}"
log "  Redsocks config: ${REDSOCKS_CONF}"
log "  Systemd unit: ${SYSTEMD_UNIT_DEST}"
log "  iptables chain: ${CHAIN_NAME}"
