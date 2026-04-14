<p align="center">
  <img src="https://img.shields.io/badge/Cangjie-SoonLink-ff6b35?style=for-the-badge&labelColor=1a1a2e" alt="SoonLink" />
  <img src="https://img.shields.io/badge/version-0.5.27-4f8cff?style=for-the-badge&labelColor=1a1a2e" alt="Version" />
  <img src="https://img.shields.io/badge/license-Apache%202.0-2ea043?style=for-the-badge&labelColor=1a1a2e" alt="License" />
</p>

# SoonLink / 溯联

> 拥有一座私人跨端文件仓库，从未如此简单。

SoonLink 是基于 **仓颉编程语言** 与 **Ignite** 构建的开源文件管理与跨端传输服务端。它聚焦“自己掌握数据、自己定义流转、自己接入自动化”，把文件浏览、分块上传、目录传输、CLI 与 MCP 收成一个可持续演进的基础能力面。

## 为什么选择 SoonLink

- **私有化与自托管友好**：数据与运行环境都掌握在自己手中，不依赖第三方云盘。
- **跨端传输闭环**：保留文件浏览、分块上传、Range 下载、目录任务与基础设备管理。
- **自动化优先**：自带 CLI 与 `stdio` MCP，适合 agent、tasker 与脚本工作流。
- **仓颉生态原生实现**：以 Ignite 为 Web 承载，以 lisi 提供生态补位，便于在当前仓颉环境中落地。
- **免代码客户端**：内置 [StaticWeb](./web) 服务，开箱即用，无需前端开发。
- **模块化扩展，便于二次开发**：适合社区协作、自托管部署与二次开发，提供 MCP (Model Context Protocol) Server 和 CLI，支持二次开发和深度定制。

## 快速开始

### 使用源码构建

```bash
git clone https://github.com/Celading/SoonLink.git
cd SoonLink
cjpm build
cjpm test
cjpm run
```

默认入口：

- Web：<http://localhost:8081>
- Swagger：<http://localhost:8081/swagger>

### 关于依赖

> 当前仓库的 `cjpm.toml` 已按默认依赖入口配置 Ignite 与 lisi。若你的环境使用本地镜像、私有源或离线依赖，请按实际构建环境改写依赖来源。

- 仓颉sdk环境 [`cangjie-sdk`](https://cangjie-lang.cn/download) v1.1.0+
- 仓颉标准扩展库 [`cangjie-stdx`](https://gitcode.com/Cangjie/cangjie_stdx/releases/v1.1.0-beta.24.1)
  >如需[`仓颉 nightly[含stdx链接]`](https://gitcode.com/Cangjie/nightly_build)

### CLI / MCP

```bash
./target/release/bin/main version
./target/release/bin/main status --config ./config/soonlink.toml
./target/release/bin/main devices
./target/release/bin/main fs-list --path /
./target/release/bin/main mcp
```

### 首次运行

默认读取以下内容(如果没有则创建)：
- `./config/soonlink.toml`
- `./config/devices.json`

## 核心能力

- **文件与目录**：文件浏览、文件元信息、文本读取、目录任务与目录树保留复制。
- **传输链路**：分块上传、合并写入、Range 下载、传输任务追踪。
- **设备与授信基础**：手动设备注册、设备状态、信任状态、PIN 配对基础能力。
- **自动化入口**：CLI、MCP、Swagger、HTTP API。
- **工程形态**：源码构建、CI 检查链路与可持续演进的仓库结构。

## API 速览

- **运行态与上下文**：`GET /api/health`、`GET /api/ready`、`GET /api/session/context`
- **文件系统**：`GET /api/fs/list`、`GET /api/fs/info`、`GET /api/fs/encoding`、`GET /api/fs/line`
- **分块传输**：`POST /api/transfer/chunk/session`、`PUT /api/transfer/chunk/session/:id/chunks/:index`、`POST /api/transfer/chunk/session/:id/complete`、`GET /api/transfer/chunk/files/:fileId`
- **任务**：`GET /api/tasks`、`POST /api/tasks`、`GET /api/tasks/:id`、`DELETE /api/tasks/:id`
- **设备与授信**：`GET /api/devices`、`POST /api/devices/register`、`POST /api/devices/:id/trust`、`POST /api/devices/:id/pairing/pin`、`POST /api/devices/:id/pairing/confirm`

## 文档与入口

- [Manual Home](./manual/README.md)
- [Manual API](./manual/API.md)
- [CLI & MCP](./manual/docs/cli-and-mcp.md)
- [Web Console](./manual/docs/web-console.md)
- [问题排查](./manual/docs/troubleshooting.md)
- [Skills Index](./manual/skills/README.md)

## 项目结构

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

## 支持平台

| 系统 / 平台 | 架构 / 机型线 | 状态 | 说明 |
|:---|:---|:---:|:---|
| macOS | aarch64 (Apple Silicon) | ✅ | 默认开发主线之一 |
| macOS | x86_64 (Intel) | ✅ | 已覆盖 |
| Linux | x86_64/aarch64 | ✅ | 通用 GNU/Linux |
| EulerOS | Taishan/x86_64 | ✅ | 与通用 Linux |
| Windows | x86_64 | ✅ | 默认 Windows 兼容线 |
| OpenHarmony | aarch64/x86_64 | ✅ | OHOS 适配线 |
| HarmonyOS | arm64/Lingxi | ✅ | 终端 / 设备侧部署线 |
| LoongArch | LoongArch64 | 规划中 | 后续平台扩展预留 |

## 许可证

SoonLink 基于 [Apache License 2.0](LICENSE) 开源。
