# SoonLink Skills Index

这里放的是公开版也适合暴露出去的 SoonLink 使用范式，而不是内部团队规约。

## 推荐先看

- [CLI 与 MCP 技能手册](./cli-and-mcp.md)
  - 适合第一次接入 SoonLink Core，或想把 SoonLink 接进 agent 自动化流程时使用。

## Core 版最值得先掌握的技能

- **版本与能力确认**
  - 先用 `soonlnk version` 和 `soonlnk capabilities` 确认当前 edition、版本号和能力标签。
- **状态先行**
  - 先看 `config` / `status` / `connectors`，再做设备登记、授信和传输。
- **设备登记与授信**
  - 手工登记节点、PIN 配对、显式 trust 是最稳的 Core 联调入口。
- **路径总结后再传输**
  - 对文件或目录先 `summary`，确认路径语义、条目数和估算体积，再创建任务。
- **MCP 要先读状态再动手**
  - 让 agent 先查 `soonlink_status`、`soonlink_list_devices`、`soonlink_summarize_path`，再发起传输。

## 提 issue 前建议准备

- 版本号
- edition
- 命令行或 MCP 调用参数
- 源设备 / 目标设备 / 路径
- `status` 与 `summary` 输出
- 最终任务状态

## 使用边界

`skills/` 适合沉淀：

- 可以对外公开的使用模板
- 可重复执行的联调顺序
- 适合 agent / CLI / MCP 复用的动作链

`skills/` 不适合沉淀：

- 团队内部执行痕迹
- 私有商用能力说明
- `_helper` 内部决策与风险记录
