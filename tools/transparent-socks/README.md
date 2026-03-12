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

## Layout

```text
.
├── README.md
├── setup.sh
├── remove.sh
├── status.sh
├── config.env.example
├── files/
│   └── redsocks.conf.template
├── systemd/
│   └── redsocks-transparent.service
└── tests/
    └── smoke-test.sh
```

## Requirements

* Ubuntu 24.04
* root access
* outbound access to a SOCKS proxy
* `iptables` support
* `systemd`

## Quick start

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

## Config options

### Proxy settings

* `PROXY_TYPE`
  Supported by this tool: `socks5`, `socks4`, `http-connect`

* `PROXY_HOST`
  IP or hostname of the upstream proxy

* `PROXY_PORT`
  Upstream proxy port

* `PROXY_USER`

* `PROXY_PASS`

### redsocks listener

* `REDSOCKS_LOCAL_IP`
* `REDSOCKS_LOCAL_PORT`

### iptables behavior

* `CHAIN_NAME`
* `BYPASS_UID`
* `EXTRA_BYPASS_CIDRS`
* `EXTRA_BYPASS_PORTS`

### generated files

* `REDSOCKS_CONF`
* `SYSTEMD_UNIT_DEST`
* `IPTABLES_SAVE_FILE`

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

