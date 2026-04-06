# SoonLink 0.5.22

拥有一座私人跨端文件仓库，从未如此简单。

## Highlights

- Manual node records now carry full endpoint metadata, including `scheme`, `host`, `port`, and `basePath`.
- SoonLink node connectors can now talk to `https` targets and deployments mounted behind reverse-proxy subpaths.
- Validation has been tightened so invalid `soonlink-http` endpoint schemes are rejected even when the connector type is inferred.

## Included

- Endpoint-aware device modeling across Web, CLI, MCP, automation runtime, and registry persistence
- Reverse-proxy / base-path aware SoonLink node client URLs
- Regression coverage for endpoint normalization, registry roundtrip, server validation, and MCP registration
- Version and release references synchronized to `0.5.22`

## Upgrade Notes

- If your remote SoonLink node is exposed under a subpath such as `/soonlink`, fill that path into `basePath` for the manual node record.
- Existing plain `http://host:port` manual nodes continue to work without additional migration.
- Update build and release references to `0.5.22`.

## Bundles

- `linux-x86_64`
- `linux-aarch64`
- `darwin-x86_64`
- `darwin-aarch64`
- `windows-x86_64`

## Checks

- `cjpm test`
- endpoint-model regression suite
- public boundary audit
