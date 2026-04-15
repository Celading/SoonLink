# SoonLink Skills Index

This folder is meant for reusable SoonLink usage patterns, not internal team-only governance.

## Start here

- [CLI and MCP Skills](./cli-and-mcp-EN.md)
  - Use this first when you are onboarding a SoonLink node or wiring it into an agent workflow.

## The most valuable skills

- **verify runtime and capability state first**
  - Start with `soonlnk version` and `soonlnk capabilities`.
- **inspect state before acting**
  - Check `config`, `status`, and `connectors` before registration, trust, or transfer work.
- **treat registration and trust as first-class workflows**
  - Manual node registration plus PIN pairing is the safest onboarding path.
- **summarize paths before transfer**
  - Use `summary` to confirm path semantics, entry count, and estimated size before creating a task.
- **make MCP agents read before they write**
  - Agents should call `soonlink_status`, `soonlink_list_devices`, and `soonlink_summarize_path` before they enqueue transfers.

## Capture this before filing an issue

- version
- capability tags
- exact CLI or MCP input
- source device, target device, and path
- `status` output
- `summary` output
- final task status

## Boundary

`skills/` is a good place for:

- reusable usage patterns
- repeatable integration sequences
- CLI / MCP / agent-friendly task chains

`skills/` is not a good place for:

- internal execution notes
- sensitive operational details
- `_helper` risk logs or internal decision records
