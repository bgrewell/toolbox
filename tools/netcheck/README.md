# netcheck

Network interface information and connectivity testing for Linux.

## What it does

- Displays physical network interfaces with driver, firmware, bus, speed, and port details
- Lists VLAN interfaces with link and VID
- Shows PCIe device details for network adapters
- Displays DNS server configuration via `resolvectl`
- Shows the routing table
- Performs connectivity tests: gateway ping, internet ping (with and without DNS), webpage download, and throughput measurement
- Supports Open vSwitch interface parsing
- Outputs formatted tables or JSON

## Prerequisites

- Python 3.6+
- System tools: `ip`, `ethtool`, `lspci`, `ping`, `wget`, `resolvectl`
- Open vSwitch commands require `sudo`

## Quick start

### Run directly (no install)

```bash
curl -fsSL https://raw.githubusercontent.com/bgrewell/toolbox/main/tools/netcheck/netcheck.py | python3
```

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/bgrewell/toolbox/main/tools/netcheck/install.sh | sudo bash
```

Once installed, run with:

```bash
netcheck            # interfaces + VLANs (default)
netcheck -a         # all tables
netcheck -t         # connectivity tests
```

### Remove

```bash
curl -fsSL https://raw.githubusercontent.com/bgrewell/toolbox/main/tools/netcheck/remove.sh | sudo bash
```

## CLI reference

### Display tables

| Flag | Description |
|------|-------------|
| `-I`, `--interfaces` | Physical interfaces table |
| `-V`, `--vlans` | VLAN interfaces table |
| `-D`, `--dns` | DNS server table |
| `-R`, `--routes` | Route table |
| `-P`, `--pcie` | PCIe device details |
| `-a`, `--all` | All tables |

### Operational

| Flag | Description |
|------|-------------|
| `-t`, `--test` | Run connectivity tests |
| `-j`, `--json` | Output as JSON |
| `-o`, `--ovs` | Parse Open vSwitch interfaces (requires sudo) |
| `-v`, `--version` | Show version |

### Formatting and filtering

| Flag | Description |
|------|-------------|
| `-u`, `--up` | Only show interfaces that are UP |
| `-s`, `--summary` | Shorter summary format |
| `-b`, `--barebones` | Narrow format, easy to import |
| `-c`, `--clear` | Clear console before output |

## Notes

- With no flags, netcheck defaults to showing interfaces and VLANs.
- Connectivity tests (`-t`) are not included with `-a`; they must be explicitly requested.
- OVS parsing (`-o`) requires sudo for `ovs-vsctl`.
