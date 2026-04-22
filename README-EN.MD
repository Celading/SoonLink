<p align="center">
  <img src="https://img.shields.io/badge/Cangjie-SoonLink-ff6b35?style=for-the-badge&labelColor=1a1a2e" alt="SoonLink" />
  <img src="https://img.shields.io/badge/version-0.0.2-4f8cff?style=for-the-badge&labelColor=1a1a2e" alt="Version" />
  <img src="https://img.shields.io/badge/license-Apache%202.0-2ea043?style=for-the-badge&labelColor=1a1a2e" alt="License" />
</p>

# SoonLink / Suolian

> Owning a private cross-device file hub has never been simpler.

SoonLink is a file-management and cross-device transfer service built with **Cangjie** and **Ignite**. It is shaped around self-hosted control, programmable transfer flows, relay caching, and automation-ready entrypoints such as CLI and MCP.

## Why SoonLink

- **Self-hosted by default**: keep both your data and runtime under your own control.
- **Baseline transfer loop included**: file browsing, chunk upload, range download, directory tasks, and baseline device management.
- **Relay cache accepts temporary text**: paste short-lived text into the Web console and SoonLink stores it as a UTF-8 `.txt` record for preview, restore, and download.
- **Automation first**: ships CLI and `stdio` MCP entrypoints for agents, taskers, and scripts.
- **Native to the current Cangjie ecosystem**: Ignite carries the Web surface, while lisi fills ecosystem gaps.
- **No-code client included**: ships with the built-in [StaticWeb](./web) service, ready to use without separate frontend development.
- **Modular and extensible**: suitable for collaborative maintenance, self-hosted deployment, and downstream customization, while exposing MCP (Model Context Protocol) Server and CLI surfaces for deep integration.

## Quick Start

### Build from source

```bash
git clone https://github.com/Celading/SoonLink.git
cd SoonLink
cjpm build
cjpm test
cjpm run
```

Default entrypoints:

- Web: <http://localhost:8081>
- Swagger: <http://localhost:8081/swagger>

### Dependency note

> The repository `cjpm.toml` is already aligned to the default Ignite and lisi sources. If your environment relies on local mirrors, private registries, or offline dependencies, replace those dependency sources to match your build environment.

- Cangjie SDK environment [`cangjie-sdk`](https://cangjie-lang.cn/download) v1.1.0+
- Cangjie standard extension library [`cangjie-stdx`](https://gitcode.com/Cangjie/cangjie_stdx/releases/v1.1.0-beta.24.1)
  > If needed, use [`Cangjie nightly` with stdx link included](https://gitcode.com/Cangjie/nightly_build)

### CLI / MCP

```bash
./target/release/bin/main version
./target/release/bin/main status --config ./config/soonlink.toml
./target/release/bin/main devices
./target/release/bin/main fs-list --path /
./target/release/bin/main mcp
```

### First Run

SoonLink reads the following files by default and creates them if missing:

- `./config/soonlink.toml`
- `./config/devices.json`

## Core Capabilities

- **Files and directories**: browsing, metadata lookup, text reading, directory tasks, and tree-preserving copies.
- **Transfer pipeline**: chunk upload, merged writes, range download, and task tracking.
- **Relay cache**: file relay, temporary text records, restore-to-path flows, record-level deletion, and expiry cleanup.
- **Device and trust foundations**: manual registration, device state, trust state, and PIN pairing foundations.
- **Automation surfaces**: CLI, MCP, Swagger, and HTTP APIs.
- **Engineering shape**: source builds, CI checks, and a repository layout that can keep evolving.

## API Overview

- **Runtime and session**: `GET /api/health`, `GET /api/ready`, `GET /api/session/context`
- **File system**: `GET /api/fs/list`, `GET /api/fs/info`, `GET /api/fs/encoding`, `GET /api/fs/line`
- **Chunk transfer**: `POST /api/transfer/chunk/session`, `PUT /api/transfer/chunk/session/:id/chunks/:index`, `POST /api/transfer/chunk/session/:id/complete`, `GET /api/transfer/chunk/files/:fileId`
- **Relay cache**: `GET /api/relay/jobs`, `POST /api/relay/jobs`, `POST /api/relay/jobs/text`, `GET /api/relay/jobs/:id/cache`, `GET /api/relay/jobs/:id/preview`, `DELETE /api/relay/jobs/:id`
- **Tasks**: `GET /api/tasks`, `POST /api/tasks`, `GET /api/tasks/:id`, `DELETE /api/tasks/:id`
- **Devices and trust**: `GET /api/devices`, `POST /api/devices/register`, `POST /api/devices/:id/trust`, `POST /api/devices/:id/pairing/pin`, `POST /api/devices/:id/pairing/confirm`

## Docs and Entry Points

- [Manual Home](./manual/README-EN.md)
- [Manual API](./manual/API-EN.md)
- [CLI & MCP](./manual/docs/cli-and-mcp-EN.md)
- [Web Console](./manual/docs/web-console-EN.md)
- [Troubleshooting](./manual/docs/troubleshooting-EN.md)
- [Skills Index](./manual/skills/README-EN.md)

## Project Layout

```text
SoonLink/
├── cjpm.toml
├── config/
├── src/
│   ├── commons/
│   ├── features/
│   ├── master/
│   ├── product/
│   └── tests/
├── web/
├── scripts/
└── manual/
```

## Supported Platforms

| System / Platform | Architecture / Device Line | Status | Notes |
|:---|:---|:---:|:---|
| macOS | aarch64 (Apple Silicon) | ✅ | One of the default development lines |
| macOS | x86_64 (Intel) | ✅ | Covered |
| Linux | x86_64 / aarch64 | ✅ | General GNU/Linux |
| EulerOS | Taishan / x86_64 | ✅ | Aligned with general Linux support |
| Windows | x86_64 | ✅ | Default Windows compatibility line |
| OpenHarmony | aarch64 / x86_64 | ✅ | OHOS adaptation line |
| HarmonyOS | arm64 / Lingxi | ✅ | Terminal and device-side deployment line |
| LoongArch | LoongArch64 | Planned | Reserved for later platform expansion |

## License

SoonLink is open sourced under [Apache License 2.0](LICENSE).
