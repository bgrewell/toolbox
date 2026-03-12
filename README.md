# Toolbox

A collection of self-contained tools and scripts for sysadmin, development, and security work.

## Repository structure

```
toolbox/
├── tools/           # Self-contained tools, each with its own README
├── lib/
│   ├── bash/        # Shared Bash utilities
│   └── python/      # Shared Python utilities
└── docs/            # Project-wide documentation
```

## Tools

| Tool | Description | Platform |
|------|-------------|----------|
| [netcheck](tools/netcheck/) | Network interface info and connectivity testing | Linux |
| [transparent-socks](tools/transparent-socks/) | Transparent outbound TCP proxying via `redsocks` and `iptables` | Linux (Ubuntu 24.04) |

## Usage

Each tool lives in its own directory under `tools/` and is fully self-contained — with its own README, install steps, and configuration. Navigate to a tool's directory and follow its README to get started.

Shared helper functions are available under `lib/` for tools that need common Bash or Python utilities.

## Contributing

To add a new tool:

1. Create a directory under `tools/` with a descriptive name.
2. Include a `README.md` covering what the tool does, prerequisites, and usage.
3. Keep it self-contained — all scripts, configs, and supporting files belong in the tool's directory.
4. If the tool uses shared utilities from `lib/`, document that dependency.

## License

[MIT](https://opensource.org/licenses/MIT)
