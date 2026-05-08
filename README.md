<p align="center">
  <img src="https://img.shields.io/badge/Cangjie-SoonLink-ff6b35?style=for-the-badge&labelColor=1a1a2e" alt="SoonLink" />
  <img src="https://img.shields.io/badge/version-0.5.56-4f8cff?style=for-the-badge&labelColor=1a1a2e" alt="Version" />
  <img src="https://img.shields.io/badge/license-Apache%202.0-2ea043?style=for-the-badge&labelColor=1a1a2e" alt="License" />
</p>
<div align="center">
<span style="font-weight:300;font-size:38px">SoonLink / 溯联</span><br/>
<span style="font-weight:100;font-size:26px">拥有一座私人跨端文件仓库，从未如此简单</span>
<p align="center">
  <sub>文件传输 · 私有化 · 文件内容中转 · 集成管理页面 · 可扩展</sub>
</p>
</div>
<p align="center">
  <a href="https://atomgit.com/cinyu/SoonLink">GitCode</a> ·
  <a href="https://github.com/celading/SoonLink">GitHub</a> ·
  <a href="https://cnb.cool/CinexusOwn/SoonLink">CNB</a>
</p>

SoonLink 是基于 ***仓颉编程语言*** 与 ***Ignite*** 构建的文件管理与跨端传输服务端。致力于把文件浏览、分块上传、目录传送、中转站缓存、CLI 与 MCP 收拢成一个轻巧、透明的基础能力层，让你“数据在手，规则自己定，自动流转自由安排”。

## 为什么选择 SoonLink

- **私有化的主场**：数据与服务都跑在你自己的环境里，不依赖第三方云盘，隐私如自家书房。
- **跨端流转，一气呵成**：浏览器直览文件、分块可靠上传、Range 按需下载、目录传输任务与基础设备管理，环环相扣。
- **临时文本也有“中转站”**：浏览器端想随手存一段文字？直接写入中转缓存，生成 UTF-8 `.txt`，随时回流、下载、再编辑。
- **自动化友好**：原生提供 CLI 与 `stdio` MCP，方便接入 agent、脚本、定时任务等自动化工作流。
- **仓颉生态原生**：Ignite 承载 Web 服务，lisi 提供生态补位，自然融入仓颉开发环境。
- **零前端开销**：内置 [StaticWeb](./web)，启动即得 Web 控制台，不用额外写一行前端代码。
- **模块化、易扩展**：MCP Server、CLI、清晰的模块分层，方便二次开发与社区一起打磨。

## 快速开始

### 2. 拉取代码 & 构建
> 本项目需要仓颉运行时 v1.1.0以上
。详见：

```bash
git clone https://github.com/Celading/SoonLink.git
cd SoonLink
cjpm build
cjpm test
```

### 3. 启动服务
```bash
cjpm run
```

默认入口：

- 主界面：`http://localhost:8081`
- API 文档（Swagger）：`http://localhost:8081/swagger`

### 关于依赖

> 首次运行会自动生成默认配置文件 `./config/soonlink.toml` 和 `./config/devices.json`（若不存在），无需手动创建。

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

可直接在终端中管理文件、查看设备、启动 MCP 服务，与自动化流程无缝衔接。

### 首次运行

默认读取以下内容(如果没有则创建)：
- `./config/soonlink.toml`
- `./config/devices.json`

## 核心能力

- **文件与目录**：文件浏览、文件元信息、文本读取、目录任务与目录树保留复制。
- **传输链路**：分块上传、合并写入、Range 下载、传输任务追踪。
- **中转站缓存**：文件中转、临时文本记录、缓存回流、记录级删除与过期清理。
- **设备与授信基础**：手动设备注册、设备状态、信任状态、PIN 配对基础能力。
- **自动化入口**：CLI、MCP、Swagger、HTTP API。
- **工程形态**：源码构建、CI 检查链路与可持续演进的仓库结构。

## 📡 API 速览 (最常用接口)

- **运行状态**  
  `GET /api/health` · `GET /api/ready` · `GET /api/session/context`

- **文件系统**  
  `GET /api/fs/list` · `GET /api/fs/info` · `GET /api/fs/encoding` · `GET /api/fs/line`

- **分块传输**  
  `POST /api/transfer/chunk/session` · `PUT …/chunks/:index` · `POST …/complete` · `GET …/files/:fileId`

- **中转站**  
  `GET /api/relay/jobs` · `POST /api/relay/jobs` · `POST …/text` · `GET …/cache` · `GET …/preview` · `DELETE …/:id`

- **任务管理**  
  `GET /api/tasks` · `POST /api/tasks` · `GET …/:id` · `DELETE …/:id`

- **设备与配对**  
  `GET /api/devices` · `POST …/register` · `POST …/trust` · `POST …/pairing/pin` · `POST …/pairing/confirm`

完整接口文档请查看 Swagger 或 [Manual API](./manual/API.md)。

## 文档与入口

- [📘 手册首页](./manual/README.md)
- [📙 API 详细说明](./manual/API.md)
- [💻 CLI & MCP 使用指南](./manual/docs/cli-and-mcp.md)
- [🌐 Web 控制台说明](./manual/docs/web-console.md)
- [🔧 问题排查手册](./manual/docs/troubleshooting.md)
- [🧩 技能索引（Skills）](./manual/skills/README.md)

## 项目结构

本项目遵循 [毫末(Haomo)](https://gitcode.com/cinyu/Haomo)目录风格与哲学

```text
SoonLink/
├── cjpm.toml            # 项目与依赖配置
├── config/              # 运行时配置
├── src/
│   ├── commons/         # 公共组件
│   ├── features/        # 功能模块
│   ├── master/          # 核心调度
│   ├── product/         # 产品组装
│   └── tests/           # 测试套件
├── web/                 # 内置前端静态资源
├── scripts/             # 辅助脚本
└── manual/              # 详细文档
```

## 支持平台

| 系统 / 平台 | 架构 / 机型线 | 状态 | 说明 |
|:---|:---|:---:|:---|
| macOS | Apple Silicon (aarch64) | ✅ | 主力开发环境 |
| macOS | Intel (x86_64) | ✅ | 完整支持 |
| Linux | x86_64 / aarch64 | ✅ | 通用 GNU/Linux 发行版 |
| EulerOS | Taishan / x86_64 | ✅ | 兼容通用 Linux |
| Windows | x86_64 | ✅ | 默认 Windows 兼容线 |
| OpenHarmony | aarch64/x86_64 | ✅ | OHOS 适配线 |
| HarmonyOS | arm64/Lingxi | ✅ | 终端与设备侧部署 |
| LoongArch | LoongArch64 | 规划中 | 后续平台扩展预留 |

## 许可证

SoonLink 采用 [Apache License 2.0](LICENSE) 开源，欢迎自由使用、修改与协作。
