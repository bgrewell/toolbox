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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1"
    exit 1
  }
}

log() {
  printf '[*] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

die() {
  printf '[x] %s\n' "$*" >&2
  exit 1
}

apt_install_if_missing() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    log "installing package: $pkg"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
  fi
}

validate_required_vars() {
  : "${PROXY_TYPE:?missing PROXY_TYPE}"
  : "${PROXY_HOST:?missing PROXY_HOST}"
  : "${PROXY_PORT:?missing PROXY_PORT}"
  : "${REDSOCKS_LOCAL_IP:?missing REDSOCKS_LOCAL_IP}"
  : "${REDSOCKS_LOCAL_PORT:?missing REDSOCKS_LOCAL_PORT}"
  : "${CHAIN_NAME:?missing CHAIN_NAME}"
  : "${REDSOCKS_CONF:?missing REDSOCKS_CONF}"
  : "${SYSTEMD_UNIT_DEST:?missing SYSTEMD_UNIT_DEST}"
  : "${IPTABLES_SAVE_FILE:?missing IPTABLES_SAVE_FILE}"
}

validate_proxy_type() {
  case "$PROXY_TYPE" in
    socks4|socks5|http-connect)
      ;;
    *)
      die "unsupported PROXY_TYPE: $PROXY_TYPE"
      ;;
  esac
}

resolve_ipv4s() {
  local host="$1"

  if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%s\n' "$host"
    return 0
  fi

  getent ahostsv4 "$host" | awk '{print $1}' | sort -u
}

build_auth_block() {
  if [[ -n "${PROXY_USER:-}" && -n "${PROXY_PASS:-}" ]]; then
    cat <<EOF
  login = "${PROXY_USER}";
  password = "${PROXY_PASS}";
EOF
  elif [[ -n "${PROXY_USER:-}" || -n "${PROXY_PASS:-}" ]]; then
    die "both PROXY_USER and PROXY_PASS must be set together"
  fi
}

generate_redsocks_conf() {
  local template="files/redsocks.conf.template"
  local auth_block
  auth_block="$(build_auth_block || true)"

  [[ -f "$template" ]] || die "template file not found: $template"

  mkdir -p "$(dirname "$REDSOCKS_CONF")"

  sed \
    -e "s|__REDSOCKS_LOCAL_IP__|$REDSOCKS_LOCAL_IP|g" \
    -e "s|__REDSOCKS_LOCAL_PORT__|$REDSOCKS_LOCAL_PORT|g" \
    -e "s|__PROXY_HOST__|$PROXY_HOST|g" \
    -e "s|__PROXY_PORT__|$PROXY_PORT|g" \
    -e "s|__PROXY_TYPE__|$PROXY_TYPE|g" \
    -e "/__AUTH_BLOCK__/{
      s|__AUTH_BLOCK__|$auth_block|
    }" \
    "$template" > "$REDSOCKS_CONF"
}

install_systemd_unit() {
  mkdir -p "$(dirname "$SYSTEMD_UNIT_DEST")"
  install -m 0644 "systemd/redsocks-transparent.service" "$SYSTEMD_UNIT_DEST"
  systemctl daemon-reload
  systemctl enable redsocks-transparent.service
}

start_redsocks() {
  systemctl restart redsocks-transparent.service
  systemctl --no-pager --full status redsocks-transparent.service || true
}

chain_exists() {
  iptables -t nat -S "$CHAIN_NAME" >/dev/null 2>&1
}

remove_existing_chain() {
  iptables -t nat -D OUTPUT -p tcp -j "$CHAIN_NAME" 2>/dev/null || true

  if chain_exists; then
    iptables -t nat -F "$CHAIN_NAME" 2>/dev/null || true
    iptables -t nat -X "$CHAIN_NAME" 2>/dev/null || true
  fi
}

add_return_rule_dest() {
  local dest="$1"
  iptables -t nat -A "$CHAIN_NAME" -d "$dest" -j RETURN
}

add_return_rule_port() {
  local port="$1"
  iptables -t nat -A "$CHAIN_NAME" -p tcp --dport "$port" -j RETURN
}

add_return_rule_uid() {
  local uid="$1"
  iptables -t nat -A "$CHAIN_NAME" -m owner --uid-owner "$uid" -j RETURN
}

setup_iptables() {
  local proxy_ips=()
  mapfile -t proxy_ips < <(resolve_ipv4s "$PROXY_HOST")

  log "rebuilding iptables chain: $CHAIN_NAME"
  remove_existing_chain
  iptables -t nat -N "$CHAIN_NAME"

  # Reserved/local/private ranges
  add_return_rule_dest "0.0.0.0/8"
  add_return_rule_dest "10.0.0.0/8"
  add_return_rule_dest "127.0.0.0/8"
  add_return_rule_dest "169.254.0.0/16"
  add_return_rule_dest "172.16.0.0/12"
  add_return_rule_dest "192.168.0.0/16"
  add_return_rule_dest "224.0.0.0/4"
  add_return_rule_dest "240.0.0.0/4"

  # Do not redirect traffic headed to the upstream proxy itself
  if ((${#proxy_ips[@]} == 0)); then
    warn "could not resolve proxy host '$PROXY_HOST' to an IPv4 address"
    warn "using a literal IP for PROXY_HOST is recommended"
  else
    for ip in "${proxy_ips[@]}"; do
      add_return_rule_dest "${ip}/32"
    done
  fi

  # Avoid redirect loops into local redsocks port
  add_return_rule_port "$REDSOCKS_LOCAL_PORT"

  # Optional excluded ports
  for port in ${EXTRA_BYPASS_PORTS:-}; do
    add_return_rule_port "$port"
  done

  # Optional excluded networks
  for cidr in ${EXTRA_BYPASS_CIDRS:-}; do
    add_return_rule_dest "$cidr"
  done

  # Optional owner bypass
  if [[ -n "${BYPASS_UID:-}" ]]; then
    add_return_rule_uid "$BYPASS_UID"
  fi

  # Redirect all remaining local outbound TCP into redsocks
  iptables -t nat -A "$CHAIN_NAME" -p tcp -j REDIRECT --to-ports "$REDSOCKS_LOCAL_PORT"

  # Hook the chain into local-originating TCP traffic
  iptables -t nat -A OUTPUT -p tcp -j "$CHAIN_NAME"
}

persist_iptables() {
  mkdir -p "$(dirname "$IPTABLES_SAVE_FILE")"
  iptables-save > "$IPTABLES_SAVE_FILE"
}

main() {
  require_cmd apt-get
  require_cmd dpkg
  require_cmd iptables
  require_cmd iptables-save
  require_cmd getent
  require_cmd sed
  require_cmd install
  require_cmd systemctl

  validate_required_vars
  validate_proxy_type

  apt_install_if_missing redsocks
  apt_install_if_missing iptables
  apt_install_if_missing iptables-persistent

  generate_redsocks_conf
  install_systemd_unit
  start_redsocks
  setup_iptables
  persist_iptables

  log "setup complete"
  log "redsocks config: $REDSOCKS_CONF"
  log "systemd unit: $SYSTEMD_UNIT_DEST"
  log "iptables chain: $CHAIN_NAME"
  log "upstream proxy: ${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}"
}

main "$@"
