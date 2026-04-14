# SoonLink CLI and MCP Skills

## When to use this guide

Use this guide when you want to:

- drive a SoonLink node directly through the `soonlnk` CLI,
- connect SoonLink to an agent host over MCP,
- reduce a bug report into the smallest reproducible workflow.

## Recommended bootstrap order

When you first touch a SoonLink node, start in this order:

1. `soonlnk version`
2. `soonlnk capabilities`
3. `soonlnk config --config ./config/config.toml`
4. `soonlnk status --config ./config/config.toml`
5. `soonlnk connectors --config ./config/config.toml`

That gives you the node identity, version, effective config, runtime state, and available connector bindings before you try anything destructive.

## CLI quick recipes

### Version and capability checks

```bash
soonlnk version
soonlnk capabilities
```

These are the fastest way to confirm:

- whether you are really on the expected SoonLink node,
- whether the runtime version matches your docs and release page,
- whether the expected capability tags are present.

### Config and runtime state

```bash
soonlnk config --config ./config/config.toml
soonlnk status --config ./config/config.toml
```

Check these fields first:

- `webPort`
- `rootDir`
- `tempDir`
- `relayEnabled`
- `enableMdns`

If the UI behaves differently from what you expected, these commands are usually faster than inspecting the frontend first.

### Devices, tasks, and connectors

```bash
soonlnk devices --config ./config/config.toml
soonlnk tasks --config ./config/config.toml
soonlnk connectors --config ./config/config.toml
```

Target one item by id when needed:

```bash
soonlnk devices --id office-node --config ./config/config.toml
soonlnk tasks --id task-123 --config ./config/config.toml
```

### Register a manual device

```bash
soonlnk register-device \
  --id office-node \
  --name "Office Mac" \
  --ip 192.168.1.20 \
  --port 8081 \
  --scheme http \
  --base-path /soonlink \
  --config ./config/config.toml
```

This is especially useful for:

- two-node local testing,
- manual fallback when active discovery is unavailable,
- validating SoonLink-to-SoonLink connectivity before polishing the UI.

### Trust and PIN pairing

```bash
soonlnk pair-device-pin --id office-node --config ./config/config.toml
soonlnk confirm-device-pin --id office-node --pin 123456 --config ./config/config.toml
soonlnk trust-device --id office-node --state trusted --config ./config/config.toml
```

The safer order is:

1. `pair-device-pin`
2. `confirm-device-pin`
3. only then perform the transfer

For quick local debugging, `trust-device` is fine, but PIN pairing is the better long-term workflow.

### File and directory flows

```bash
soonlnk fs-list --device local --path / --config ./config/config.toml
soonlnk fs-info --device local --path /docs/readme.txt --config ./config/config.toml
soonlnk summary --device local --path /source --config ./config/config.toml
soonlnk transfer \
  --source-device local \
  --target-device office-node \
  --file-path /source \
  --target-path /incoming \
  --config ./config/config.toml
```

The practical order is:

1. `fs-list`
2. `fs-info`
3. `summary`
4. `transfer`

That confirms path existence, source type, expected entry count, and estimated size before you enqueue the task.

## MCP patterns

SoonLink currently exposes these MCP tools for agents:

- `soonlink_status`
- `soonlink_capabilities`
- `soonlink_list_devices`
- `soonlink_list_tasks`
- `soonlink_list_connectors`
- `soonlink_register_device`
- `soonlink_remove_device`
- `soonlink_set_device_trust`
- `soonlink_start_device_pin_pairing`
- `soonlink_confirm_device_pin_pairing`
- `soonlink_list_dir`
- `soonlink_get_file_info`
- `soonlink_summarize_path`
- `soonlink_create_transfer_task`

### Recommended agent workflow

If you are wiring SoonLink into an agent workflow, use this order:

1. `soonlink_status`
2. `soonlink_capabilities`
3. `soonlink_list_devices`
4. `soonlink_register_device` when the node is missing
5. trust or PIN-pair the device
6. `soonlink_summarize_path`
7. `soonlink_create_transfer_task`

That keeps the agent from blindly creating transfer tasks before the node, trust state, and source path are verified.

## Minimal issue intake

Before filing an issue, capture:

- current version,
- current node identity,
- exact command line,
- source device, target device, and path,
- `status` output,
- `summary` output,
- final task status.

That is usually enough to localize most SoonLink issues quickly.

## One-line takeaway

SoonLink CLI and MCP work best when you treat them as “inspect the real state first, automate second.”
