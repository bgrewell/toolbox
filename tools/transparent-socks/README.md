# transparent-socks

Transparent outbound TCP proxying for Linux using `redsocks` and `iptables`.

This tool is intended for Ubuntu 24.04 and configures the local system so that outbound TCP connections are transparently redirected through a SOCKS proxy.

## What it does

* Installs and configures `redsocks`
* Creates `iptables` NAT rules to redirect outbound TCP traffic
* Excludes loopback, RFC1918/private ranges, multicast, broadcast, and the proxy server itself
* Supports setup, removal, and status inspection

## What it does not do

This tool is primarily for transparent **TCP** proxying.

It does **not** fully solve:

* generic UDP proxying
* DNS leak prevention in all cases
* gateway/router mode for forwarding traffic from other hosts

## Requirements

* Ubuntu 24.04
* root access
* outbound access to a SOCKS proxy
* `iptables` support
* `systemd`

## Quick start

### Install (remote, one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/bgrewell/toolbox/main/tools/transparent-socks/install.sh \
  | sudo bash -s -- --proxy 203.0.113.10 --proxy-port 1080
```

### Uninstall (remote, one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/bgrewell/toolbox/main/tools/transparent-socks/uninstall.sh \
  | sudo bash
```

### Install (local clone)

Copy and edit the config:

```bash
cp config.env.example config.env
vim config.env
```

Run setup:

```bash
sudo ./setup.sh ./config.env
```

Check status:

```bash
sudo ./status.sh ./config.env
```

Remove everything:

```bash
sudo ./remove.sh ./config.env
```

## Install options

| Flag | Description | Default |
|------|-------------|---------|
| `--proxy HOST` | Upstream proxy host (required) | — |
| `--proxy-port PORT` | Upstream proxy port | `1080` |
| `--proxy-type TYPE` | `socks4`, `socks5`, or `http-connect` | `socks5` |
| `--proxy-user USER` | Proxy username | — |
| `--proxy-pass PASS` | Proxy password | — |
| `--redsocks-ip IP` | Local redsocks listen IP | `127.0.0.1` |
| `--redsocks-port PORT` | Local redsocks listen port | `18086` |
| `--chain NAME` | iptables NAT chain name | `REDSOCKS` |
| `--bypass-uid UID` | UID whose traffic bypasses proxy | — |
| `--bypass-cidrs "CIDRS"` | Space-separated CIDRs to bypass | — |
| `--bypass-ports "PORTS"` | Space-separated ports to bypass | `22` |

## Uninstall options

| Flag | Description | Default |
|------|-------------|---------|
| `--chain NAME` | iptables NAT chain name to remove | `REDSOCKS` |
| `--purge` | Also remove redsocks config file | off |

## Layout

```text
.
├── README.md
├── install.sh           # curl-friendly installer with CLI flags
├── uninstall.sh         # curl-friendly uninstaller
├── setup.sh             # local installer (reads config.env)
├── remove.sh            # local uninstaller (reads config.env)
├── status.sh
├── config.env.example
├── files/
│   └── redsocks.conf.template
├── systemd/
│   └── redsocks-transparent.service
└── tests/
    └── smoke-test.sh
```

## Notes

### SSH safety

By default, port `22` is bypassed to reduce the chance of locking yourself out during remote administration.

### DNS

DNS may still leak depending on resolver behavior and application behavior.

### Hostname proxy targets

If `PROXY_HOST` is a hostname, setup will resolve it at script runtime and exclude the resolved IPv4 addresses from redirection. Using a static IP is still preferred for reliability.

## Development

Run the smoke test:

```bash
bash tests/smoke-test.sh
```

Run shellcheck if installed:

```bash
shellcheck setup.sh remove.sh status.sh tests/smoke-test.sh
```

