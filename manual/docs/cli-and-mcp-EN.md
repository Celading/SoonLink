# CLI and MCP

SoonLink ships two automation-facing entrypoints by default:

- CLI for scripts, terminals, CI, and quick diagnostics
- `stdio` MCP for agents, taskers, IDE flows, and AI-assisted workflows

## Common CLI Commands

```bash
./target/release/bin/main version
./target/release/bin/main status --config ./config/soonlink.toml
./target/release/bin/main devices
./target/release/bin/main fs-list --path /
./target/release/bin/main mcp
```

## When CLI Helps

- checking version, capability tags, and runtime state
- reading device, path, and task state quickly
- verifying whether the current config is effective
- reproducing issues with the smallest surface possible

## When MCP Helps

- letting an agent inspect runtime state, devices, and the file tree
- letting an agent create transfer tasks or browse directories
- serving as a unified bridge for external automation systems

## Suggestions

- start troubleshooting with `version` and `status`
- prefer `mcp` when the workflow is AI- or agent-driven
- keep the real automation logic in CLI / MCP even when the Web UI is only a presentation layer
