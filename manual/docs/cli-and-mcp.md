# CLI 与 MCP

SoonLink 开源版默认带两套自动化入口：

- CLI：更适合脚本、终端、CI 与快速诊断
- `stdio` MCP：更适合 agent、tasker 与 IDE / AI 工作流

## 常用 CLI

```bash
./target/release/bin/main version
./target/release/bin/main status --config ./config/soonlink.toml
./target/release/bin/main devices
./target/release/bin/main fs-list --path /
./target/release/bin/main mcp
```

## CLI 适合做什么

- 查询版本、edition 与能力标签
- 获取设备列表、路径信息与任务列表
- 快速验证当前配置是否生效
- 做最小可复现排障

## MCP 适合做什么

- 让 agent 读取运行状态、设备和文件树
- 让 agent 创建传输任务或做目录探查
- 作为外部自动化系统的统一桥接层

## 建议

- 调试时先跑 `version` 与 `status`
- 涉及 AI / agent 时优先开 `mcp`
- 当 Web 只是展示层时，把真实自动化流程放到 CLI / MCP
